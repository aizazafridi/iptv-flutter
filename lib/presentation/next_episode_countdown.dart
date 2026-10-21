import 'package:flutter/material.dart';
import '../domain/models.dart';

class NextEpisodeCountdown extends StatefulWidget {
  final Episode episode;
  final VoidCallback onPlay, onCancel;
  const NextEpisodeCountdown({
    super.key,
    required this.episode,
    required this.onPlay,
    required this.onCancel,
  });
  @override
  State<NextEpisodeCountdown> createState() => _NextEpisodeCountdownState();
}

class _NextEpisodeCountdownState extends State<NextEpisodeCountdown>
    with SingleTickerProviderStateMixin {
  late final timer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  bool activated = false;
  final playFocus = FocusNode();
  void play() {
    if (activated) return;
    activated = true;
    timer.stop();
    widget.onPlay();
  }

  void cancel() {
    activated = true;
    timer.stop();
    widget.onCancel();
  }

  @override
  void initState() {
    super.initState();
    timer.addStatusListener((status) {
      if (status == AnimationStatus.completed) play();
    });
    timer.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) playFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    playFocus.dispose();
    timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: 310,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xee17151f),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white38),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 5,
          height: 100,
          child: AnimatedBuilder(
            animation: timer,
            builder: (_, _) => Semantics(
              label: 'Next episode countdown',
              value: '${(timer.value * 100).round()}%',
              child: ColoredBox(
                color: Colors.white12,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: timer.value,
                    widthFactor: 1,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: timer,
                builder: (_, _) => Text(
                  'Next episode in ${(10 * (1 - timer.value)).ceil()} seconds',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.episode.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Row(
                children: [
                  TextButton(
                    autofocus: true,
                    focusNode: playFocus,
                    onPressed: play,
                    child: const Text('Play now'),
                  ),
                  TextButton(onPressed: cancel, child: const Text('Cancel')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
