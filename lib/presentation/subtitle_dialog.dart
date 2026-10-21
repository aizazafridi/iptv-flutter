import 'package:flutter/material.dart';
import 'activation_text_field.dart';
import '../data/subtitle_settings.dart';
import '../playback/subtitle_customization.dart';
import '../data/subtitle_service.dart';
import '../playback/playback_engine.dart';
import 'widgets.dart';

class OnlineSubtitleDialog extends StatefulWidget {
  final String title;
  final String? scope;
  final PlaybackEngine engine;
  final Future<void> Function(SubtitleResult result)? onSelected;
  const OnlineSubtitleDialog({
    super.key,
    required this.title,
    this.scope,
    required this.engine,
    this.onSelected,
  });
  @override
  State<OnlineSubtitleDialog> createState() => _OnlineSubtitleDialogState();
}

class _OnlineSubtitleDialogState extends State<OnlineSubtitleDialog> {
  String apiKey = '';
  int? selectedId;
  late final TextEditingController titleController = TextEditingController(
    text: widget.title,
  );
  late final settings = SubtitleSettings(scope: widget.scope);
  String language = 'en';
  bool busy = true;
  String? error;
  List<SubtitleResult>? results;
  @override
  void initState() {
    super.initState();
    loadKey();
  }

  Future<void> loadKey() async {
    try {
      final key = await settings.load();
      if (mounted) apiKey = key;
    } catch (_) {
      error = 'Could not read saved subtitle settings.';
    }
    if (mounted) {
      setState(() => busy = false);
      if (apiKey.isNotEmpty) {
        await search();
      } else {
        setState(() => error = 'Set up online subtitles in Settings first.');
      }
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (apiKey.isEmpty || titleController.text.trim().isEmpty) {
      setState(
        () =>
            error = 'Enter a title and configure online subtitles in Settings.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      selectedId = null;
      results = null;
    });
    try {
      final key = apiKey;
      final rows = await SubtitleService(
        key,
      ).search(titleController.text.trim(), language);
      if (!mounted) return;
      setState(() => results = rows);
      if (rows.isNotEmpty) await apply(rows.first);
    } catch (exception) {
      if (mounted) setState(() => error = safeMessage(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply(SubtitleResult result) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final uri = await SubtitleService(apiKey).download(result);
      if (!mounted) return;
      if (widget.engine is SubtitleCustomizationEngine) {
        await (widget.engine as SubtitleCustomizationEngine).addNamedSubtitle(
          uri,
          result.label,
        );
      } else {
        await widget.engine.addSubtitle(uri);
      }
      await widget.onSelected?.call(result);
      if (mounted) {
        setState(() {
          selectedId = result.fileId;
          busy = false;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = 'Could not apply subtitle: ${safeMessage(exception)}';
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Subtitles'),
    contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    content: SizedBox(
      width: 340,
      height: 300,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ActivationTextField(
              controller: titleController,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Movie or series title',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: language,
              decoration: const InputDecoration(labelText: 'Subtitle language'),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                DropdownMenuItem(value: 'fr', child: Text('French')),
                DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                DropdownMenuItem(value: 'ur', child: Text('Urdu')),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => language = value!),
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            if (results != null && results!.isEmpty)
              const Text(
                'No subtitles found. Try a shorter title or another language.',
              ),
            if (selectedId != null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Best match selected. Choose another if timing differs.',
                ),
              ),
            if (results != null)
              for (final result in results!)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  selected: selectedId == result.fileId,
                  title: Text(
                    result.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    selectedId == result.fileId
                        ? Icons.check_circle
                        : Icons.download,
                  ),
                  onTap: busy ? null : () => apply(result),
                ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton(
        onPressed: busy ? null : search,
        child: const Text('Search again'),
      ),
    ],
  );
}
