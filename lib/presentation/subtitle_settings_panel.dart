import 'package:flutter/material.dart';
import '../data/subtitle_settings.dart';

class SubtitleSettingsPanel extends StatefulWidget {
  final String? scope;
  const SubtitleSettingsPanel({super.key, this.scope});
  @override
  State<SubtitleSettingsPanel> createState() => _SubtitleSettingsPanelState();
}

class _SubtitleSettingsPanelState extends State<SubtitleSettingsPanel> {
  final controller = TextEditingController();
  late final settings = SubtitleSettings(scope: widget.scope);
  bool busy = true;
  String? message;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final key = await settings.load();
      if (mounted) controller.text = key;
    } catch (_) {
      message = 'Could not read subtitle settings.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await settings.save(controller.text);
      if (mounted) setState(() => message = 'Subtitle settings saved.');
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not save subtitle settings. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Online subtitles', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text(
        'This key is used by default when searching and downloading subtitles.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: controller,
        enabled: !busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: 'OpenSubtitles API key'),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Save subtitle settings'),
        ),
      ),
      if (message != null) Text(message!),
    ],
  );
}
