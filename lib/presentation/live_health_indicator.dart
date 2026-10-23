import 'dart:async';
import 'package:flutter/material.dart';

/// Observes the current stream without opening an extra provider connection.
class LiveHealthIndicator extends StatefulWidget {
  final Duration position;
  final bool playing, starting, buffering, reconnecting;
  const LiveHealthIndicator({
    super.key,
    required this.position,
    required this.playing,
    required this.starting,
    required this.buffering,
    required this.reconnecting,
  });
  @override
  State<LiveHealthIndicator> createState() => _LiveHealthIndicatorState();
}

class _LiveHealthIndicatorState extends State<LiveHealthIndicator> {
  final clock = Stopwatch()..start();
  Duration? lastProgress;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LiveHealthIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.starting && !oldWidget.starting) lastProgress = null;
    if (widget.position > oldWidget.position) lastProgress = clock.elapsed;
  }

  @override
  void dispose() {
    timer?.cancel();
    clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stalled =
        lastProgress != null &&
        clock.elapsed - lastProgress! > const Duration(seconds: 8);
    final label = widget.reconnecting
        ? 'Reconnecting'
        : widget.starting
        ? 'Connecting'
        : widget.buffering || stalled
        ? 'Unstable'
        : !widget.playing
        ? 'Paused'
        : lastProgress == null
        ? 'Checking'
        : 'Good';
    final color = label == 'Good'
        ? Colors.greenAccent
        : label == 'Reconnecting'
        ? Colors.redAccent
        : Colors.amber;
    return Tooltip(
      message:
          'Channel health: $label. Based on playback progress and buffering.',
      child: Semantics(
        label: 'Channel health: $label',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, color: color, size: 8),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
