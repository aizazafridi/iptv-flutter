import 'package:flutter/material.dart';
import '../playback/video_display.dart';

class VideoDisplayDialog extends StatefulWidget {
  final VideoDisplayEngine engine;
  final bool zoom;
  const VideoDisplayDialog({
    super.key,
    required this.engine,
    this.zoom = false,
  });
  @override
  State<VideoDisplayDialog> createState() => _VideoDisplayDialogState();
}

class _VideoDisplayDialogState extends State<VideoDisplayDialog> {
  late VideoDisplay display = widget.engine.videoDisplay;
  void update({String? ratio, double? zoom, Offset? pan}) => setState(() {
    display = VideoDisplay(
      ratio: ratio ?? display.ratio,
      pan: pan ?? display.pan,
      zoom: (zoom ?? display.zoom).clamp(0.5, 3.0),
    );
    widget.engine.setVideoDisplay(display);
  });
  void move(double dx, double dy) => update(
    pan: Offset(
      (display.pan.dx + dx).clamp(-0.5, 0.5),
      (display.pan.dy + dy).clamp(-0.5, 0.5),
    ),
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.zoom ? 'Zoom' : 'Aspect ratio'),
    contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    content: SizedBox(
      width: 260,
      child: widget.zoom
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(display.zoom * 100).round()}%',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Zoom out',
                      onPressed: () => update(zoom: display.zoom - 0.1),
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0.5,
                        max: 3,
                        divisions: 25,
                        value: display.zoom,
                        onChanged: (value) => update(zoom: value),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zoom in',
                      onPressed: () => update(zoom: display.zoom + 0.1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Move video'),
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => move(0, 0.05),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Move left',
                      icon: const Icon(Icons.keyboard_arrow_left),
                      onPressed: () => move(0.05, 0),
                    ),
                    IconButton(
                      tooltip: 'Center video',
                      icon: const Icon(Icons.center_focus_strong),
                      onPressed: () => update(pan: Offset.zero),
                    ),
                    IconButton(
                      tooltip: 'Move right',
                      icon: const Icon(Icons.keyboard_arrow_right),
                      onPressed: () => move(-0.05, 0),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Move down',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => move(0, -0.05),
                ),
                TextButton(
                  onPressed: () => update(zoom: 1, pan: Offset.zero),
                  child: const Text('Reset zoom'),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ratio in VideoDisplay.ratios)
                    ListTile(
                      dense: true,
                      title: Text(ratio),
                      trailing: display.ratio == ratio
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () {
                        update(ratio: ratio);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
