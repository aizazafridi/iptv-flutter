import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../domain/models.dart';

/// An overlay on the existing video surface; never owns playback.
class NextEpisodeCountdown extends StatefulWidget {
  final Episode episode;
  final VoidCallback onPlay, onCancel;
  final VoidCallback? onEpisodes;
  final String? seriesTitle;
  final Uri? artwork;
  final bool countdown, paused;
  final FocusNode? playFocus;
  const NextEpisodeCountdown({
    super.key,
    required this.episode,
    required this.onPlay,
    required this.onCancel,
    this.onEpisodes,
    this.seriesTitle,
    this.artwork,
    this.countdown = true,
    this.paused = false,
    this.playFocus,
  });
  @override
  State<NextEpisodeCountdown> createState() => _NextEpisodeCountdownState();
}

class _NextEpisodeCountdownState extends State<NextEpisodeCountdown>
    with SingleTickerProviderStateMixin {
  late final timer = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 15),
  );
  bool activated = false;
  void play() {
    if (activated || widget.paused) return;
    activated = true;
    timer.stop();
    widget.onPlay();
  }

  @override
  void initState() {
    super.initState();
    timer.addStatusListener((status) {
      if (status == AnimationStatus.completed) play();
    });
    updateTimer();
  }

  void updateTimer() {
    if (widget.countdown && !widget.paused && !activated) {
      if (!timer.isAnimating) timer.forward();
    } else {
      timer.stop();
    }
  }

  @override
  void didUpdateWidget(covariant NextEpisodeCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.countdown && !widget.countdown) timer.reset();
    updateTimer();
  }

  @override
  void dispose() {
    timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.episode.artwork ?? widget.artwork;
    return Container(
      width: 340,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xf51b212b),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Up Next',
                style: TextStyle(
                  color: Color(0xff90caf9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: image == null
                  ? const ColoredBox(
                      color: Color(0xff293443),
                      child: Icon(Icons.live_tv, color: Colors.white54),
                    )
                  : CachedNetworkImage(
                      imageUrl: image.toString(),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: Color(0xff293443),
                        child: Icon(Icons.live_tv, color: Colors.white54),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.seriesTitle != null)
            Text(
              widget.seriesTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          Text(
            'S${widget.episode.season} E${widget.episode.number} \u00b7 ${widget.episode.title}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: timer,
                  builder: (context, _) {
                    final fill = widget.countdown ? timer.value : 1.0;
                    final label = widget.countdown
                        ? 'Play Next (${(15 * (1 - timer.value)).ceil()}s)'
                        : 'Play Next';
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: const Color(0xff465263)),
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                key: const ValueKey('up-next-button-fill'),
                                widthFactor: fill,
                                heightFactor: 1,
                                child: const ColoredBox(color: Colors.white),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              focusNode: widget.playFocus,
                              style: ButtonStyle(
                                padding: const WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                ),
                                overlayColor: const WidgetStatePropertyAll(
                                  Colors.transparent,
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
                              onPressed: play,
                              child: ShaderMask(
                                blendMode: BlendMode.srcIn,
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: const [
                                    Colors.black,
                                    Colors.black,
                                    Colors.white,
                                    Colors.white,
                                  ],
                                  stops: [0, fill, fill, 1],
                                ).createShader(bounds),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.play_arrow,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              TextButton(
                onPressed: () {
                  activated = true;
                  timer.stop();
                  widget.onCancel();
                },
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          if (widget.onEpisodes != null)
            TextButton(
              onPressed: widget.onEpisodes,
              child: const Text(
                'Back to Episodes',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
