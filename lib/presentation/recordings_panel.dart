import 'package:flutter/material.dart';
import '../data/recorded_segments.dart';

class RecordingsPanel extends StatelessWidget {
  final RecordedSegments segments;
  final String title;
  final Future<void> Function()? onStop;
  const RecordingsPanel({
    super.key,
    required this.segments,
    required this.title,
    this.onStop,
  });
  Future<void> delete(BuildContext context, RecordedSegment? segment) async {
    if (segment == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete all recordings?'),
          content: const Text(
            'Delete saved recordings for this movie or episode?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete all'),
            ),
          ],
        ),
      );
      if (!context.mounted || confirmed != true) return;
    }
    try {
      await segments.delete(segment);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete recordings. Please retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    alignment: Alignment.topRight,
    insetPadding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
    child: SizedBox(
      width: 320,
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Theme(
            data: ThemeData.dark(),
            child: ListenableBuilder(
              listenable: segments,
              builder: (context, _) {
                return Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recordings',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete all recordings',
                          onPressed: segments.saving || segments.entries.isEmpty
                              ? null
                              : () => delete(context, null),
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                        IconButton(
                          tooltip: 'Close recordings',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (segments.activeLoop != null)
                      TextButton.icon(
                        onPressed: onStop ?? () => segments.loop(null),
                        icon: const Icon(Icons.repeat_on),
                        label: const Text('Stop recording playback'),
                      ),
                    const Divider(),
                    Expanded(
                      child: segments.entries.isEmpty
                          ? const Center(
                              child: Text('No recordings for this selection.'),
                            )
                          : ListView.builder(
                              itemCount: segments.entries.length,
                              itemBuilder: (_, index) {
                                final segment = segments.entries[index];
                                return ListTile(
                                  title: Text('Recording ${index + 1}'),
                                  subtitle: Text(segment.label),
                                  selected: identical(
                                    segment,
                                    segments.activeLoop,
                                  ),
                                  leading: const Icon(Icons.repeat),
                                  trailing: IconButton(
                                    tooltip: 'Delete recording ${index + 1}',
                                    onPressed: segments.saving
                                        ? null
                                        : () => delete(context, segment),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                  onTap: segments.saving
                                      ? null
                                      : () => Navigator.pop(context, segment),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
