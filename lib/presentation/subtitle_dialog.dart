import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/subtitle_settings.dart';
import '../playback/subtitle_customization.dart';
import '../data/subtitle_service.dart';
import '../playback/playback_engine.dart';
import 'widgets.dart';

const subtitleLanguages = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'ar': 'Arabic',
  'hi': 'Hindi',
  'ur': 'Urdu',
};

/// Presentation only: the original release label and filename remain untouched.
({String title, String details}) subtitleResultDisplay(SubtitleResult result) {
  final parts = result.label.split(RegExp(r'\s*\u00b7\s*'));
  final release = result.releaseName.isNotEmpty
      ? result.releaseName
      : parts.first;
  final year =
      result.year?.toString() ??
      RegExp(r'\b(?:19|20)\d{2}\b').allMatches(release).lastOrNull?.group(0);
  final resolution = RegExp(
    r'\b(?:2160p|1080p|720p|480p|4K)\b',
    caseSensitive: false,
  ).firstMatch(release)?.group(0);
  final technical = RegExp(
    r'\b(?:(?:19|20)\d{2}|2160p|1080p|720p|480p|4K|WEB[ .-]?DL|WEBRip|BluRay|HDTV)\b',
    caseSensitive: false,
  ).firstMatch(release);
  final titleBoundary = year == null
      ? technical
      : RegExp('\\b${RegExp.escape(year)}\\b').firstMatch(release) ?? technical;
  var title = result.title.isNotEmpty
      ? result.title
      : titleBoundary == null
      ? release
      : release.substring(0, titleBoundary.start);
  title = title.replaceAll(RegExp(r'[._]+'), ' ').trim();
  if (year != null) {
    title = title
        .replaceFirst(RegExp('\\s*\\(${RegExp.escape(year)}\\)\\s*\$'), '')
        .trim();
  }
  if (title.isEmpty) title = 'Subtitle';
  final after = resolution == null
      ? technical?.start
      : release.toLowerCase().indexOf(resolution.toLowerCase()) +
            resolution.length;
  final platform = RegExp(
    r'\b(?:AMZN|NF|DSNP|HMAX|ATVP|HULU|HBO)\b',
    caseSensitive: false,
  ).firstMatch(release)?.group(0);
  final source = RegExp(
    r'\b(?:WEB[ .-]?DL|WEBRip|BluRay|BDRip|HDTV|DVDRip)\b',
    caseSensitive: false,
  ).firstMatch(release)?.group(0);
  final details = source != null
      ? [platform, source].whereType<String>().join(' ')
      : after == null
      ? ''
      : release
            .substring(after)
            .replaceAll(RegExp(r'[._]+'), ' ')
            .replaceAll(RegExp(r'^[ .-]+'), '')
            .trim();
  final languageCode = result.language.isNotEmpty
      ? result.language
      : parts.length > 1
      ? parts.last
      : '';
  final language =
      subtitleLanguages[languageCode.toLowerCase()] ?? languageCode;
  return (
    title: [title, year, resolution].whereType<String>().join(' \u00b7 '),
    details: [
      details,
      language,
    ].where((value) => value.isNotEmpty).join(' \u00b7 '),
  );
}

class OnlineSubtitleDialog extends StatefulWidget {
  final String title;
  final String? scope;
  final PlaybackEngine engine;
  final Future<void> Function(SubtitleResult result)? onSelected;
  final SubtitleService? service;
  final int? selectedFileId;
  const OnlineSubtitleDialog({
    super.key,
    required this.title,
    this.scope,
    required this.engine,
    this.onSelected,
    this.service,
    this.selectedFileId,
  });
  @override
  State<OnlineSubtitleDialog> createState() => _OnlineSubtitleDialogState();
}

class _OnlineSubtitleDialogState extends State<OnlineSubtitleDialog> {
  String apiKey = '';
  late int? selectedId = widget.selectedFileId;
  final languageFocus = FocusNode(debugLabel: 'subtitle search language');
  final searchFocus = FocusNode(debugLabel: 'subtitle search again');
  final closeFocus = FocusNode(debugLabel: 'subtitle search close');
  final nodes = <int, FocusNode>{};
  final scroll = ScrollController();
  String language = 'en';
  bool busy = true, committing = false;
  int? downloadingId, focusedId;
  int revision = 0;
  String? error;
  List<SubtitleResult> results = [];
  SubtitleService get service => widget.service ?? SubtitleService(apiKey);
  @override
  void initState() {
    super.initState();
    loadKey();
  }

  Future<void> loadKey() async {
    try {
      if (widget.service == null) {
        apiKey = await SubtitleSettings(scope: widget.scope).load();
      }
      if (!mounted) return;
      if (apiKey.isNotEmpty || widget.service != null) {
        await search();
      } else {
        setState(() {
          busy = false;
          error = 'Set up online subtitles in Settings first.';
        });
        languageFocus.requestFocus();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not read saved subtitle settings.';
        });
      }
    }
  }

  @override
  void dispose() {
    revision++;
    scroll.dispose();
    for (final node in [
      languageFocus,
      searchFocus,
      closeFocus,
      ...nodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  void focusResult(int index) {
    if (!mounted || results.isEmpty) return;
    if (index < 0) {
      languageFocus.requestFocus();
      return;
    }
    if (index >= results.length) {
      searchFocus.requestFocus();
      return;
    }
    focusedId = results[index].fileId;
    final id = focusedId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || focusedId != id) return;
      if (scroll.hasClients) {
        final top = index * 86.0;
        if (top < scroll.offset ||
            top + 86 > scroll.offset + scroll.position.viewportDimension) {
          scroll.jumpTo(top.clamp(0, scroll.position.maxScrollExtent));
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusedId == id) nodes[id]?.requestFocus();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> search() async {
    if (downloadingId != null) return;
    if ((apiKey.isEmpty && widget.service == null) ||
        widget.title.trim().isEmpty) {
      setState(() {
        busy = false;
        error =
            'Current title unavailable or online subtitles are not configured.';
      });
      return;
    }
    final version = ++revision;
    setState(() {
      busy = true;
      error = null;
      results = [];
    });
    try {
      final rows = await service.search(widget.title.trim(), language);
      if (!mounted || version != revision) return;
      setState(() {
        results = rows;
        busy = false;
      });
      if (rows.isNotEmpty) {
        var best = 0;
        for (var i = 1; i < rows.length; i++) {
          if (rows[i].score > rows[best].score) best = i;
        }
        focusResult(best);
      } else {
        searchFocus.requestFocus();
      }
    } catch (exception) {
      if (mounted && version == revision) {
        setState(() {
          error = safeMessage(exception);
          busy = false;
        });
        searchFocus.requestFocus();
      }
    }
  }

  Future<void> apply(SubtitleResult result) async {
    if (busy) return;
    final version = revision;
    setState(() {
      busy = true;
      downloadingId = result.fileId;
      error = null;
    });
    try {
      if (selectedId != result.fileId) {
        final uri = await service.download(result);
        if (!mounted || version != revision) return;
        setState(() => committing = true);
        if (widget.engine is SubtitleCustomizationEngine) {
          await (widget.engine as SubtitleCustomizationEngine).addNamedSubtitle(
            uri,
            result.label,
          );
        } else {
          await widget.engine.addSubtitle(uri);
        }
        if (!mounted) return;
        setState(() => selectedId = result.fileId);
      }
      await widget.onSelected?.call(result);
      if (mounted) {
        setState(() => committing = false);
        Navigator.pop(context);
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          busy = false;
          downloadingId = null;
          committing = false;
          error = selectedId == result.fileId
              ? 'Subtitle loaded, but its preference could not be saved. Select it again to retry.'
              : 'Could not load subtitle: ${safeMessage(exception)}';
        });
        focusResult(
          results.indexWhere((entry) => entry.fileId == result.fileId),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !committing,
    child: AlertDialog(
      backgroundColor: const Color(0xff1b212b),
      surfaceTintColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 600),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      title: const Text(
        'Find Subtitles',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height * .55).clamp(260.0, 420.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              focusNode: languageFocus,
              initialValue: language,
              decoration: const InputDecoration(
                labelText: 'Subtitle language',
                labelStyle: TextStyle(fontSize: 13),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xff64b5f6)),
                ),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 18,
                ),
              ),
              items: [
                for (final entry in subtitleLanguages.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => language = value!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Available subtitles',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '${results.length} ${results.length == 1 ? 'result' : 'results'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffadb9c8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (busy)
              const LinearProgressIndicator(
                minHeight: 2,
                color: Color(0xff64b5f6),
              ),
            if (downloadingId != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Downloading and loading subtitle\u2026',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  error!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffffb4ab),
                  ),
                ),
              ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        busy
                            ? 'Searching\u2026'
                            : error == null
                            ? 'No subtitles found. Try a shorter title or another language.'
                            : '',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      itemExtent: 86,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        final text = subtitleResultDisplay(result);
                        final selected = selectedId == result.fileId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent ||
                                  event is KeyRepeatEvent) {
                                final at = results.indexWhere(
                                  (row) => row.fileId == focusedId,
                                );
                                if (event.logicalKey ==
                                        LogicalKeyboardKey.arrowUp ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown) {
                                  focusResult(
                                    at +
                                        (event.logicalKey ==
                                                LogicalKeyboardKey.arrowUp
                                            ? -1
                                            : 1),
                                  );
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft) {
                                  closeFocus.requestFocus();
                                  return KeyEventResult.handled;
                                }
                                if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                                  searchFocus.requestFocus();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextButton(
                              key: ValueKey('online-subtitle-${result.fileId}'),
                              focusNode: nodes.putIfAbsent(
                                result.fileId,
                                () => FocusNode(
                                  debugLabel:
                                      'online subtitle ${result.fileId}',
                                ),
                              ),
                              onPressed: busy ? null : () => apply(result),
                              style: ButtonStyle(
                                alignment: Alignment.centerLeft,
                                padding: const WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                foregroundColor: const WidgetStatePropertyAll(
                                  Colors.white,
                                ),
                                backgroundColor: WidgetStatePropertyAll(
                                  selected
                                      ? const Color(0xff293e53)
                                      : const Color(0xff252e3a),
                                ),
                                shape: WidgetStatePropertyAll(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                ),
                                side: WidgetStateProperty.resolveWith(
                                  (states) => BorderSide(
                                    color: states.contains(WidgetState.focused)
                                        ? const Color(0xff64b5f6)
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          text.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 12,
                                            height: 1.1,
                                          ),
                                        ),
                                        if (text.details.isNotEmpty)
                                          Text(
                                            text.details,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xffadb9c8),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.download_outlined,
                                    color: selected
                                        ? const Color(0xff64b5f6)
                                        : const Color(0xffadb9c8),
                                    size: 21,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      actions: [
        TextButton(
          focusNode: closeFocus,
          style: TextButton.styleFrom(
            minimumSize: const Size(88, 48),
            textStyle: const TextStyle(fontSize: 13),
          ),
          onPressed: committing ? null : () => Navigator.pop(context),
          child: const Text(
            'Close',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        FilledButton(
          focusNode: searchFocus,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff64b5f6),
            foregroundColor: const Color(0xff111820),
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onPressed: busy ? null : search,
          child: const Text('Search Again', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}
