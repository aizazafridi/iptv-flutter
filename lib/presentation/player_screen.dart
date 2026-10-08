import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../playback/playback_engine.dart';
import '../playback/media_kit_engine.dart';

class PlayerScreen extends StatefulWidget {
  final PlaybackSource source;
  final PlaybackEngine Function()? engineFactory;
  const PlayerScreen({super.key, required this.source, this.engineFactory});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final PlaybackEngine engine;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false, fullscreen = false, starting = true;
  double? dragPosition;
  String? error;
  @override
  void initState() {
    super.initState();
    engine = widget.engineFactory?.call() ?? MediaKitEngine();
    subscriptions.add(
      engine.position.listen((value) {
        if (mounted) setState(() => position = value);
      }),
    );
    subscriptions.add(
      engine.duration.listen((value) {
        if (mounted) setState(() => duration = value);
      }),
    );
    subscriptions.add(
      engine.playing.listen((value) {
        if (mounted) {
          setState(() {
            playing = value;
            if (value) starting = false;
          });
        }
      }),
    );
    subscriptions.add(
      engine.errors.listen((value) {
        if (mounted) {
          setState(() {
            error = value;
            starting = false;
          });
        }
      }),
    );
    start();
  }

  Future<void> start() async {
    setState(() {
      error = null;
      starting = true;
    });
    try {
      await engine.open(widget.source);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not start playback. Please retry.';
          starting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(engine.dispose());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> seek(Duration target) async {
    if (widget.source.isLive || duration <= Duration.zero) return;
    final milliseconds = target.inMilliseconds.clamp(
      0,
      duration.inMilliseconds - 1,
    );
    await engine.seek(Duration(milliseconds: milliseconds));
  }

  void toggleFullscreen() {
    setState(() => fullscreen = !fullscreen);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  String time(Duration value) {
    final seconds = value.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    final hours = seconds ~/ 3600;
    return '${hours > 0 ? '$hours:' : ''}${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !fullscreen,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) toggleFullscreen();
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () =>
            engine.togglePause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            engine.togglePause(),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () =>
            seek(position + const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () =>
            seek(position - const Duration(seconds: 10)),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (fullscreen) {
            toggleFullscreen();
          } else {
            Navigator.of(context).pop();
          }
        },
      },
      child: Scaffold(
        backgroundColor: const Color(0xff090b13),
        appBar: fullscreen
            ? null
            : AppBar(
                title: Text(
                  widget.source.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                backgroundColor: const Color(0xff101322),
              ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    engine.surface(),
                    if (starting && error == null)
                      const Center(child: CircularProgressIndicator()),
                    if (error != null)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          color: Colors.black87,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: start,
                                child: const Text('Retry playback'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                color: const Color(0xff15192a),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    if (!widget.source.isLive)
                      Row(
                        children: [
                          Text(
                            time(
                              Duration(
                                milliseconds:
                                    (dragPosition ??
                                            position.inMilliseconds.toDouble())
                                        .toInt(),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: duration.inMilliseconds > 0
                                  ? duration.inMilliseconds.toDouble()
                                  : 1,
                              value:
                                  (dragPosition ??
                                          position.inMilliseconds.toDouble())
                                      .clamp(
                                        0,
                                        duration.inMilliseconds > 0
                                            ? duration.inMilliseconds.toDouble()
                                            : 1,
                                      ),
                              onChangeStart: duration <= Duration.zero
                                  ? null
                                  : (value) =>
                                        setState(() => dragPosition = value),
                              onChanged: duration <= Duration.zero
                                  ? null
                                  : (value) =>
                                        setState(() => dragPosition = value),
                              onChangeEnd: duration <= Duration.zero
                                  ? null
                                  : (value) {
                                      seek(
                                        Duration(milliseconds: value.toInt()),
                                      );
                                      setState(() => dragPosition = null);
                                    },
                            ),
                          ),
                          Text(time(duration)),
                        ],
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!widget.source.isLive)
                          IconButton(
                            tooltip: 'Rewind 10 seconds',
                            onPressed: () =>
                                seek(position - const Duration(seconds: 10)),
                            icon: const Icon(Icons.replay_10),
                          ),
                        FilledButton.tonalIcon(
                          autofocus: true,
                          onPressed: engine.togglePause,
                          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          label: Text(playing ? 'Pause' : 'Play'),
                        ),
                        if (!widget.source.isLive)
                          IconButton(
                            tooltip: 'Forward 10 seconds',
                            onPressed: () =>
                                seek(position + const Duration(seconds: 10)),
                            icon: const Icon(Icons.forward_10),
                          ),
                        IconButton(
                          tooltip: fullscreen
                              ? 'Exit fullscreen'
                              : 'Fullscreen',
                          onPressed: toggleFullscreen,
                          icon: Icon(
                            fullscreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                        ),
                        if (widget.source.isLive)
                          const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Text(
                              '● LIVE',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
