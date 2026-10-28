import 'package:flutter/material.dart';
import '../playback/subtitle_customization.dart';

class SubtitleAppearanceDialog extends StatefulWidget {
  final SubtitleCustomizationEngine engine;
  const SubtitleAppearanceDialog({super.key, required this.engine});
  @override
  State<SubtitleAppearanceDialog> createState() =>
      _SubtitleAppearanceDialogState();
}

class _SubtitleAppearanceDialogState extends State<SubtitleAppearanceDialog> {
  late SubtitleAppearance appearance = widget.engine.subtitleAppearance;
  void update({double? size, String? color, String? position}) => setState(() {
    appearance = SubtitleAppearance(
      size: size ?? appearance.size,
      color: color ?? appearance.color,
      position: position ?? appearance.position,
    );
    widget.engine.setSubtitleAppearance(appearance);
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(
      'Subtitle appearance',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
    ),
    content: SizedBox(
      width: 300,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<double>(
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                color: Colors.white,
              ),
              initialValue: appearance.size,
              decoration: const InputDecoration(
                labelText: 'Size',
                labelStyle: TextStyle(fontSize: 13),
              ),
              items: [
                for (final entry in {
                  18.0: 'Small',
                  24.0: 'Medium',
                  32.0: 'Large',
                  40.0: 'Extra large',
                }.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
              ],
              onChanged: (value) => update(size: value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                color: Colors.white,
              ),
              initialValue: appearance.color,
              decoration: const InputDecoration(
                labelText: 'Color',
                labelStyle: TextStyle(fontSize: 13),
              ),
              items: [
                for (final name in SubtitleAppearance.colors.keys)
                  DropdownMenuItem(
                    value: name,
                    child: Text(name, style: const TextStyle(fontSize: 14)),
                  ),
              ],
              onChanged: (value) => update(color: value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 14,
                color: Colors.white,
              ),
              initialValue: appearance.position,
              decoration: const InputDecoration(
                labelText: 'Position',
                labelStyle: TextStyle(fontSize: 13),
              ),
              items: [
                for (final name in ['Bottom', 'Middle', 'Top'])
                  DropdownMenuItem(
                    value: name,
                    child: Text(name, style: const TextStyle(fontSize: 14)),
                  ),
              ],
              onChanged: (value) => update(position: value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done', style: TextStyle(fontSize: 13)),
      ),
    ],
  );
}
