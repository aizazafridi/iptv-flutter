import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<T?> showPlayerDrawer<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  bool settings = false,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close $title',
  barrierColor: settings ? const Color(0x4d000000) : Colors.black38,
  transitionDuration: const Duration(milliseconds: 230),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (context, _, _) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.pop(context),
      const SingleActivator(LogicalKeyboardKey.goBack): () =>
          Navigator.pop(context),
    },
    child: SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          key: const ValueKey('player-drawer'),
          width: (MediaQuery.sizeOf(context).width * (settings ? .32 : .30))
              .clamp(
                MediaQuery.sizeOf(context).width < 280
                    ? MediaQuery.sizeOf(context).width
                    : 280.0,
                MediaQuery.sizeOf(context).width,
              ),
          height: double.infinity,
          child: Material(
            color: settings ? const Color(0xf21b222d) : const Color(0xff1b212b),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(9),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: settings ? 22 : 25,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close $title',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: builder(context)),
                  const SizedBox(height: 8),
                  const Text(
                    '\u2191 \u2193 Select \u00b7 OK apply \u00b7 Back close',
                    style: TextStyle(fontSize: 12, color: Color(0xffadb9c8)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

class PlayerOption {
  final String id, label;
  final String? section;
  const PlayerOption(this.id, this.label, {this.section});
}

Future<String?> showPlayerOptions(
  BuildContext context, {
  required String title,
  required List<PlayerOption> options,
  String? selected,
  bool settings = false,
}) => showPlayerDrawer<String>(
  context,
  title: title,
  settings: settings,
  builder: (_) => _PlayerOptionsList(
    options: options,
    selected: selected,
    settings: settings,
    fitLabels: title == 'Subtitles',
  ),
);

class _PlayerOptionsList extends StatefulWidget {
  final List<PlayerOption> options;
  final String? selected;
  final bool settings, fitLabels;
  const _PlayerOptionsList({
    required this.options,
    this.selected,
    this.settings = false,
    this.fitLabels = false,
  });
  @override
  State<_PlayerOptionsList> createState() => _PlayerOptionsListState();
}

class _PlayerOptionsListState extends State<_PlayerOptionsList> {
  late final scroll = ScrollController(initialScrollOffset: initialOffset());
  double initialOffset() {
    final index = widget.options.indexWhere(
      (option) => option.id == widget.selected,
    );
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += widget.settings ? 60 : 51;
      if (widget.options[i].section != null &&
          (i == 0 ||
              widget.options[i - 1].section != widget.options[i].section)) {
        offset += 43;
      }
    }
    return offset;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final selected = widget.selected;
    return ListView.builder(
      controller: scroll,
      itemCount: options.isEmpty ? 1 : options.length,
      itemBuilder: (context, i) {
        if (options.isEmpty) return const Text('No tracks available');
        final option = options[i];
        final selectedOption = option.id == selected;
        final startsSection =
            option.section != null &&
            (i == 0 || options[i - 1].section != option.section);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (startsSection) ...[
              const Divider(color: Colors.white12, height: 18),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  option.section!,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xffadb9c8),
                  ),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.only(bottom: widget.settings ? 8 : 5),
              child: TextButton(
                key: ValueKey('player-option-${option.id}'),
                autofocus:
                    selected == null || !options.any((o) => o.id == selected)
                    ? i == 0
                    : selectedOption,
                style: ButtonStyle(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: WidgetStatePropertyAll(
                    Size(double.infinity, widget.settings ? 52 : 46),
                  ),
                  maximumSize: WidgetStatePropertyAll(
                    Size(double.infinity, widget.settings ? 52 : 46),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  alignment: Alignment.centerLeft,
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => widget.settings
                        ? states.contains(WidgetState.focused)
                              ? const Color(0xff34465f)
                              : const Color(0xff27313e)
                        : selectedOption
                        ? const Color(0xff293e53)
                        : const Color(0xff252e3a),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        widget.settings ? 14 : 9,
                      ),
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
                  animationDuration: const Duration(milliseconds: 160),
                ),
                onPressed: () => Navigator.pop(context, option.id),
                child: Row(
                  children: [
                    Expanded(
                      child: widget.fitLabels
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                option.label,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: widget.settings ? 15 : 17,
                                  height: 1.05,
                                ),
                              ),
                            )
                          : Text(
                              option.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: widget.settings ? 15 : 17,
                                height: 1.05,
                              ),
                            ),
                    ),
                    if (selectedOption)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(Icons.check, size: 20),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Only known language codes are expanded. Qualifiers and opaque track IDs survive.
List<PlayerOption> playerTrackOptions(
  List<({String id, String label})> tracks,
) {
  const languages = <String, String>{
    'en': 'English',
    'eng': 'English',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'zh': 'Chinese',
    'zho': 'Chinese',
    'chi': 'Chinese',
    'cs': 'Czech',
    'ces': 'Czech',
    'cze': 'Czech',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fra': 'French',
    'fre': 'French',
    'de': 'German',
    'deu': 'German',
    'ger': 'German',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'ur': 'Urdu',
    'urd': 'Urdu',
    'it': 'Italian',
    'ita': 'Italian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ko': 'Korean',
    'kor': 'Korean',
    'ru': 'Russian',
    'rus': 'Russian',
    'nl': 'Dutch',
    'nld': 'Dutch',
    'dut': 'Dutch',
    'pl': 'Polish',
    'pol': 'Polish',
    'sv': 'Swedish',
    'swe': 'Swedish',
    'tr': 'Turkish',
    'tur': 'Turkish',
    'ta': 'Tamil',
    'tam': 'Tamil',
  };
  String clean(String label) {
    final parts = label
        .split(RegExp(r'\s*(?:\u00b7|\||\u00c2\u00b7)\s*'))
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.trim())
        .toList();
    final result = <String>[];
    for (final part in parts) {
      final language = languages[part.toLowerCase()];
      if (language != null &&
          parts.any(
            (other) =>
                other != part &&
                RegExp(
                  '^${RegExp.escape(language)}(?:\\s|\\(|\$)',
                  caseSensitive: false,
                ).hasMatch(other),
          )) {
        continue;
      }
      final value = language ?? part;
      if (!result.any((entry) => entry.toLowerCase() == value.toLowerCase())) {
        result.add(value);
      }
    }
    return result.isEmpty ? label : result.join(' \u00b7 ');
  }

  final labels = tracks.map((track) => clean(track.label)).toList();
  return [
    for (var i = 0; i < tracks.length; i++)
      PlayerOption(
        tracks[i].id,
        labels
                    .where(
                      (value) => value.toLowerCase() == labels[i].toLowerCase(),
                    )
                    .length >
                1
            ? '${labels[i]} \u00b7 Track ${i + 1}'
            : labels[i],
      ),
  ];
}
