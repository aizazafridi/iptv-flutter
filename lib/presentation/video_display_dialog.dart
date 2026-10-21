import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final doneFocus = FocusNode();
  late final panFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        move(-0.05, 0);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        move(0.05, 0);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        move(0, -0.05);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        move(0, 0.05);
      } else if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        doneFocus.requestFocus();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
  );
  late final zoomFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter) {
        panFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        node.previousFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  @override
  void dispose() {
    zoomFocus.dispose();
    panFocus.dispose();
    doneFocus.dispose();
    super.dispose();
  }

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
          ? SingleChildScrollView(
              child: Column(
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
                          focusNode: zoomFocus,
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
                  OutlinedButton.icon(
                    focusNode: panFocus,
                    onPressed: () => panFocus.requestFocus(),
                    icon: const Icon(Icons.open_with),
                    label: const Text('Move video'),
                  ),
                  const Text(
                    'Arrow keys move video. Select goes to Done.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: () => move(0, -0.05),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Move left',
                        icon: const Icon(Icons.keyboard_arrow_left),
                        onPressed: () => move(-0.05, 0),
                      ),
                      IconButton(
                        tooltip: 'Center video',
                        icon: const Icon(Icons.center_focus_strong),
                        onPressed: () => update(pan: Offset.zero),
                      ),
                      IconButton(
                        tooltip: 'Move right',
                        icon: const Icon(Icons.keyboard_arrow_right),
                        onPressed: () => move(0.05, 0),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => move(0, 0.05),
                  ),
                  TextButton(
                    onPressed: () => update(zoom: 1, pan: Offset.zero),
                    child: const Text('Reset zoom'),
                  ),
                ],
              ),
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
        focusNode: doneFocus,
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
