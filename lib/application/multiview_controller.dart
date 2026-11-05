import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../playback/playback_engine.dart';
import '../playback/video_display.dart';

class MultiViewPanel {
  final int id;
  MultiViewPanel(this.id);
  final surfaceKey = GlobalKey();
  ContentItem? channel;
  PlaybackSource? source;
  PlaybackEngine? engine;
  Widget? surface;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Timer? deadline, bufferWarning;
  Completer<void>? readiness;
  bool loading = false, playing = false, buffering = false;
  String? error;
}

/// Sole owner of all Multi View engines. Every mutation is serialized so layout,
/// audio changes, channel replacement and lifecycle cannot race player disposal.
class MultiViewController extends ChangeNotifier {
  final PlaybackEngine Function() createEngine;
  final Future<PlaybackSource> Function(ContentItem) resolve;
  final int? maxStreams;
  final void Function(ContentItem)? onPlayed;
  final Duration readinessTimeout;
  MultiViewController({
    required this.createEngine,
    required this.resolve,
    this.maxStreams,
    this.onPlayed,
    this.readinessTimeout = const Duration(seconds: 20),
  });
  final panels = List.generate(4, MultiViewPanel.new);
  int count = 2, selected = 0, audioId = 0;
  int? expandedId;
  bool closing = false, background = false, busy = false;
  bool names = true, logos = true, autoHide = false;
  String fit = 'Original';
  String? warning;
  Future<void> _tail = Future.value();
  Future<void>? _shutdown;
  bool _disposed = false;
  Iterable<MultiViewPanel> get visible => panels.take(count);
  MultiViewPanel get chosen => panels[selected.clamp(0, count - 1)];
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> serial(Future<void> Function() action) {
    final next = _tail.then((_) async {
      if (closing) return;
      busy = true;
      changed();
      try {
        await action();
      } finally {
        busy = false;
        changed();
      }
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  bool _current(MultiViewPanel panel, PlaybackEngine engine) =>
      !closing && !background && identical(panel.engine, engine);
  Future<void> _release(MultiViewPanel panel) async {
    panel.deadline?.cancel();
    panel.bufferWarning?.cancel();
    panel.readiness?.completeIfPending();
    final engine = panel.engine;
    panel.engine = null;
    panel.surface = null;
    panel.loading = false;
    panel.playing = false;
    panel.buffering = false;
    for (final subscription in panel.subscriptions) {
      // Unsubscribe immediately. Engine disposal owns native stream cleanup;
      // a plugin's asynchronous cancellation must not block releasing players.
      unawaited(subscription.cancel().catchError((Object _) {}));
    }
    panel.subscriptions.clear();
    changed();
    if (engine != null) {
      try {
        await (engine is AudioPlaybackEngine
            ? (engine as AudioPlaybackEngine).setVolume(0)
            : Future<void>.value());
      } catch (_) {}
      try {
        await engine.dispose();
      } catch (_) {}
    }
  }

  Future<void> _audio() async {
    // Never unmute a new player unless muting every previous owner succeeded.
    for (final panel in panels) {
      final engine = panel.engine;
      if (engine is AudioPlaybackEngine) {
        await (engine as AudioPlaybackEngine).setVolume(0);
      }
    }
    if (background || closing) return;
    final audible = panels.where((p) => p.id == audioId).firstOrNull;
    if (audible?.engine case final AudioPlaybackEngine engine) {
      await engine.setVolume(100);
    }
  }

  Future<void> _start(MultiViewPanel panel) async {
    if (closing || background || panel.source == null || panel.engine != null) {
      return;
    }
    final running = panels.where((p) => p.engine != null).length;
    if (maxStreams != null && running >= maxStreams!) {
      panel.error = 'Your provider allows $maxStreams simultaneous stream(s).';
      changed();
      return;
    }
    panel.loading = true;
    panel.error = null;
    changed();
    PlaybackEngine? candidate;
    try {
      final engine = candidate = createEngine();
      // An engine without mute support cannot safely join a Multi View session.
      if (engine is! AudioPlaybackEngine) {
        throw StateError('Audio routing unavailable');
      }
      await (engine as AudioPlaybackEngine).setVolume(0);
      if (closing || background) {
        await engine.dispose();
        return;
      }
      panel.engine = engine;
      if (engine is VideoDisplayEngine) {
        (engine as VideoDisplayEngine).setVideoDisplay(
          VideoDisplay(ratio: fit),
        );
      }
      panel.surface = engine.surface();
      final ready = panel.readiness = Completer<void>();
      void playbackReady() {
        if (!_current(panel, engine) || panel.playing) return;
        panel.loading = false;
        panel.playing = true;
        if (panel.channel != null) onPlayed?.call(panel.channel!);
        panel.deadline?.cancel();
        ready.completeIfPending();
        changed();
      }

      panel.subscriptions.add(
        engine.playing.listen((playing) {
          if (_current(panel, engine) && playing) playbackReady();
        }),
      );
      panel.subscriptions.add(
        engine.position.listen((position) {
          if (position > Duration.zero) playbackReady();
        }),
      );
      void failure() {
        if (!_current(panel, engine)) return;
        panel.error =
            'Unable to play this channel. The device or provider may have reached its playback limit. Try fewer screens.';
        panel.loading = false;
        panel.deadline?.cancel();
        ready.completeIfPending();
        changed();
        // Schedule release rather than disposing inside a native event callback.
        unawaited(
          serial(() async {
            if (identical(panel.engine, engine)) await _release(panel);
          }),
        );
      }

      panel.subscriptions.add(engine.errors.listen((_) => failure()));
      if (engine is CompletionPlaybackEngine) {
        panel.subscriptions.add(
          (engine as CompletionPlaybackEngine).completed.listen((done) {
            if (done) failure();
          }),
        );
      }
      if (engine is BufferingPlaybackEngine) {
        panel.subscriptions.add(
          (engine as BufferingPlaybackEngine).buffering.listen((value) {
            if (!_current(panel, engine) || panel.buffering == value) return;
            panel.buffering = value;
            panel.bufferWarning?.cancel();
            if (value) {
              panel.bufferWarning = Timer(const Duration(seconds: 20), () {
                if (_current(panel, engine) && panel.buffering) {
                  warning =
                      'Multiple streams may exceed your available connection speed.';
                  changed();
                }
              });
            }
            changed();
          }),
        );
      }
      panel.deadline = Timer(readinessTimeout, failure);
      changed();
      await engine.open(panel.source!).timeout(readinessTimeout);
      await ready.future;
      if (panel.error != null || closing || background) {
        if (identical(panel.engine, engine)) await _release(panel);
        return;
      }
      await _audio();
    } catch (_) {
      panel.error =
          'Unable to play this channel. Check your connection, stream support and simultaneous-stream limit.';
      panel.loading = false;
      if (panel.engine != null) {
        await _release(panel);
      } else {
        try {
          await candidate?.dispose();
        } catch (_) {}
      }
      changed();
    }
  }

  Future<void> initialize(
    PlaybackSource source,
    ContentItem? channel, {
    int layout = 2,
  }) => serial(() async {
    count = layout.clamp(2, 4);
    panels.first.source = source;
    panels.first.channel = channel;
    await _start(panels.first);
  });
  Future<void> assign(int index, ContentItem channel) => serial(() async {
    final panel = panels[index];
    if (panel.channel?.id == channel.id &&
        panel.engine != null &&
        panel.error == null) {
      return;
    }
    final runningElsewhere = panels
        .where((p) => p != panel && p.engine != null)
        .length;
    if (maxStreams != null && runningElsewhere >= maxStreams!) {
      warning =
          'Your provider allows $maxStreams simultaneous stream(s). Remove a channel before adding another.';
      changed();
      return;
    }
    // Keep the current stream alive if resolving the replacement fails.
    PlaybackSource source;
    try {
      source = await resolve(channel).timeout(readinessTimeout);
    } catch (_) {
      warning =
          'Could not resolve this channel. Check availability and provider access.';
      changed();
      return;
    }
    await _release(panel);
    panel.channel = channel;
    panel.source = source;
    await _start(panel);
  });
  Future<void> retry(int index) => serial(() async {
    final panel = panels[index];
    await _release(panel);
    if (panel.channel != null) {
      try {
        panel.source = await resolve(panel.channel!).timeout(readinessTimeout);
      } catch (_) {
        panel.error = 'Could not reconnect to this channel.';
        changed();
        return;
      }
    }
    await _start(panel);
  });
  Future<void> remove(int index) => serial(() async {
    final panel = panels[index];
    await _release(panel);
    panel.source = null;
    panel.channel = null;
    panel.error = null;
    if (audioId == panel.id) {
      audioId = visible.where((p) => p.engine != null).firstOrNull?.id ?? -1;
    }
    await _audio();
  });
  Future<void> setLayout(int value) => serial(() async {
    count = value.clamp(2, 4);
    selected = selected.clamp(0, count - 1);
    for (final panel in panels.skip(count)) {
      await _release(panel);
    }
    if (!visible.any((p) => p.id == audioId)) audioId = chosen.id;
    for (final panel in visible) {
      await _start(panel);
    }
    await _audio();
  });
  Future<void> listenTo(int index) => serial(() async {
    if (panels[index].engine == null) return;
    audioId = panels[index].id;
    await _audio();
  });
  Future<void> swap(int a, int b) => serial(() async {
    final old = panels[a];
    panels[a] = panels[b];
    panels[b] = old;
    selected = b; // Audio follows the session identity, not its grid position.
  });
  Future<void> expand(int index) => serial(() async {
    final panel = panels[index];
    if (panel.source == null) return;
    expandedId = panel.id;
    selected = index;
    audioId = panel.id;
    for (final other in panels) {
      if (other != panel) await _release(other);
    }
    await _audio();
  });
  Future<void> collapse() => serial(() async {
    expandedId = null;
    for (final panel in visible) {
      await _start(panel);
    }
    await _audio();
  });
  Future<void> setFit(String value) => serial(() async {
    fit = value;
    for (final panel in panels) {
      if (panel.engine case final VideoDisplayEngine engine) {
        engine.setVideoDisplay(VideoDisplay(ratio: value));
      }
    }
  });
  Future<void> lifecycle(bool inactive) {
    // Release readiness immediately so a background event needn't wait for timeout.
    background = inactive;
    if (inactive) {
      for (final p in panels) {
        p.readiness?.completeIfPending();
      }
    }
    return serial(() async {
      if (inactive) {
        for (final p in panels) {
          await _release(p);
        }
      } else {
        for (final p in visible) {
          if (expandedId == null || p.id == expandedId) await _start(p);
        }
        await _audio();
      }
    });
  }

  Future<void> shutdown() => _shutdown ??= () async {
    closing = true;
    for (final p in panels) {
      p.readiness?.completeIfPending();
      p.deadline?.cancel();
    }
    await _tail;
    for (final panel in panels) {
      await _release(panel);
    }
  }();
  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }
}

extension on Completer<void> {
  void completeIfPending() {
    if (!isCompleted) complete();
  }
}
