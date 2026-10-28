import 'player_settings_drawer.dart';
import 'vod_player_controls.dart';
import 'player_drawer.dart';
import 'player_episode_drawer.dart';
import 'live_tv_controls.dart';
import 'system_clock.dart';
import '../data/last_live_channel.dart';
import 'channel_list_icon.dart';
import 'live_health_indicator.dart';
import 'catch_up_panel.dart';
import '../application/video_recorder.dart';
import '../data/video_recordings.dart';
import '../playback/video_recording_engine.dart';
import 'title_access.dart';
import 'next_episode_countdown.dart';
import 'live_multiview_screen.dart';
import 'dart:async';
import '../application/watch_history.dart';
import '../playback/frame_preview.dart';
import '../playback/subtitle_customization.dart';
import '../data/subtitle_preferences.dart';
import '../data/playback_preferences.dart';
import '../data/subtitle_settings.dart';
import '../data/subtitle_service.dart';
import 'subtitle_appearance_dialog.dart';
import '../playback/video_display.dart';
import 'video_display_dialog.dart';
import 'subtitle_dialog.dart';
import 'epg_panel.dart';
import 'tv_guide_screen.dart';
import 'channel_picker.dart';
import 'live_now_playing.dart';
import 'my_list_button.dart';
import '../domain/iptv_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../playback/playback_engine.dart';
import '../playback/live_stream_recovery.dart';
import '../playback/media_kit_engine.dart';

class PlayerScreen extends StatefulWidget {
  final bool liveTvMode, initialChannelPicker, initialGuide, initialFullscreen;
  final PlaybackSource source;
  final MediaDetails? metadata;
  final IptvProvider? provider;
  final String channelCategory;
  final Future<List<ContentItem>> Function()? loadChannels;
  final Future<PlaybackSource> Function(ContentItem)? resolveChannel;
  final Future<List<EpgProgramme>> Function(ContentItem)? channelEpg;
  final Future<List<EpgProgramme>> Function()? loadEpg;
  final PlaybackEngine Function()? engineFactory;
  final WatchHistory? history;
  final ContentItem? item;
  final Episode? episode;
  final Episode? nextEpisode;
  final List<Episode> episodes;
  final Uri? seriesArtwork;
  final Duration resumeAt;
  const PlayerScreen({
    super.key,
    required this.source,
    this.metadata,
    this.liveTvMode = false,
    this.initialFullscreen = false,
    this.initialChannelPicker = false,
    this.initialGuide = false,
    this.provider,
    this.channelCategory = 'Channels',
    this.loadChannels,
    this.resolveChannel,
    this.channelEpg,
    this.loadEpg,
    this.engineFactory,
    this.history,
    this.item,
    this.episode,
    this.nextEpisode,
    this.episodes = const [],
    this.seriesArtwork,
    this.resumeAt = Duration.zero,
  });
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Episode? changedEpisode;
  Episode? get currentEpisode => changedEpisode ?? widget.episode;
  Episode? get nextEpisode {
    final index = widget.episodes.indexWhere((e) => e.id == currentEpisode?.id);
    if (index >= 0) {
      return index + 1 < widget.episodes.length
          ? widget.episodes[index + 1]
          : null;
    }
    return widget.nextEpisode;
  }

  Episode? get previousEpisode {
    final index = widget.episodes.indexWhere((e) => e.id == currentEpisode?.id);
    return index > 0 ? widget.episodes[index - 1] : null;
  }

  PlaybackSource? vodSource;
  Duration? changedResume;
  Duration get resumeAt => changedResume ?? widget.resumeAt;
  bool vodDrawerOpen = false, upNextVisible = false, autoplayNext = false;
  String selectedSubtitleId = 'auto';
  bool autoNextCancelled = false;
  Timer? hiddenSeekTimer;
  Future<void> vodOverlay(Future<void> Function() action) async {
    if (vodDrawerOpen || advancingEpisode) return;
    final previous = FocusManager.instance.primaryFocus;
    setState(() => vodDrawerOpen = true);
    controlsTimer?.cancel();
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not apply player settings. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => vodDrawerOpen = false);
        revealControls();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) previous?.requestFocus();
        });
      }
    }
  }

  Future<void> audioMenu() async {
    if (engine is! AudioTrackPlaybackEngine) return;
    final tracks = engine as AudioTrackPlaybackEngine;
    final choice = await showPlayerOptions(
      context,
      title: 'Audio',
      settings: true,
      selected: tracks.selectedAudioTrack,
      options: [
        const PlayerOption('auto', 'Automatic'),
        ...playerTrackOptions(
          tracks.currentAudioTracks
              .map((t) => (id: t.id, label: t.label))
              .toList(),
        ),
      ],
    );
    if (choice != null) await tracks.selectAudioTrack(choice);
  }

  Future<void> vodMore() async {
    await showPlayerDrawer<void>(
      context,
      title: 'Player Settings',
      settings: true,
      builder: (_) => PlayerSettingsDrawer(
        autoplay: widget.episodes.isNotEmpty ? autoplayNext : null,
        rate: playbackRate,
        seekSeconds: seekSeconds,
        ratio: engine is VideoDisplayEngine
            ? (engine as VideoDisplayEngine).videoDisplay.ratio
            : null,
        allowSpeed: !recordingLocksPlayback,
        onAutoplay: (value) async {
          setState(() => autoplayNext = value);
          await savePlaybackPreferences();
        },
        onRate: setPlaybackRate,
        onSeek: (value) async {
          setState(() => seekSeconds = value);
          await savePlaybackPreferences();
        },
        onRatio: (value) async {
          (engine as VideoDisplayEngine).setVideoDisplay(
            VideoDisplay(ratio: value),
          );
          await savePlaybackPreferences();
        },
      ),
    );
  }

  late final PlaybackEngine engine;
  late final Widget videoSurface;
  final playPauseFocus = FocusNode(debugLabel: 'player play pause');
  final liveSurfaceFocus = FocusNode(debugLabel: 'live video surface');
  bool buffering = false;
  double? bufferPercent;
  late final timelineFocus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (recordingLocksPlayback) return KeyEventResult.handled;
        if (duration <= Duration.zero) return KeyEventResult.handled;
        final step = event.logicalKey == LogicalKeyboardKey.arrowRight
            ? 10000
            : -10000;
        final target =
            ((dragPosition ?? position.inMilliseconds.toDouble()) + step).clamp(
              timelineStart.inMilliseconds.toDouble(),
              timelineEnd.inMilliseconds.toDouble(),
            );
        setState(() => dragPosition = target);
        requestPreview(Duration(milliseconds: target.toInt()));
        return KeyEventResult.handled;
      }
      if (!source.isLive &&
          (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack)) {
        return KeyEventResult.ignored;
      }
      if ([
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.goBack,
      ].contains(event.logicalKey)) {
        if (dragPosition != null) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            unawaited(seek(Duration(milliseconds: dragPosition!.toInt())));
          }
          setState(() {
            dragPosition = null;
            previewTarget = null;
            framePreview = null;
          });
        }
        hiddenSeekTimer?.cancel();
        revealControls();
        playPauseFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  DateTime lastPositionPaint = DateTime.fromMillisecondsSinceEpoch(0);
  KeyEventResult liveControlKeys(FocusNode node, KeyEvent event) {
    if (!source.isLive ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      focus?.nextFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      focus?.previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool remoteKeys(KeyEvent event) {
    if (mounted &&
        !source.isLive &&
        !vodDrawerOpen &&
        ModalRoute.of(context)?.isCurrent == true &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      if (event is KeyDownEvent) handlePlayerBack();
      return true;
    }
    if (mounted &&
        !source.isLive &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(togglePlayback());
      return true;
    }
    if (!mounted ||
        event is KeyUpEvent ||
        guideVisible ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final key = event.logicalKey;
    if (!source.isLive &&
        (upNextVisible || showAutoNext) &&
        !vodDrawerOpen &&
        dragPosition == null &&
        key == LogicalKeyboardKey.arrowUp &&
        !upNextFocus.hasFocus) {
      upNextFocus.requestFocus();
      return true;
    }
    if (upNextScope.hasFocus) return false;

    if (![
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ].contains(key)) {
      return false;
    }
    if (liveTvMode && source.isLive && !controlsVisible) {
      if (key == LogicalKeyboardKey.arrowDown) {
        revealControls();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) playPauseFocus.requestFocus();
        });
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) return true;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        unawaited(zapChannel(key == LogicalKeyboardKey.arrowLeft ? -1 : 1));
        return true;
      }
    }
    if (source.isLive && liveSurfaceFocus.hasPrimaryFocus) {
      revealControls();
      playPauseFocus.requestFocus();
      return true;
    }
    if (!source.isLive &&
        !controlsVisible &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight)) {
      if (recordingLocksPlayback || duration <= Duration.zero) {
        revealControls();
        return true;
      }
      final target =
          (position.inMilliseconds +
                  (key == LogicalKeyboardKey.arrowRight ? 10000 : -10000))
              .clamp(0, duration.inMilliseconds);
      setState(() => dragPosition = target.toDouble());
      revealControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) timelineFocus.requestFocus();
      });
      hiddenSeekTimer?.cancel();
      hiddenSeekTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || dragPosition == null) return;
        final target = dragPosition!.toInt();
        setState(() => dragPosition = null);
        unawaited(seek(Duration(milliseconds: target)));
        revealControls();
      });
      return true;
    }
    if (!controlsVisible) {
      revealControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) playPauseFocus.requestFocus();
      });
      return true; // The first press reveals controls; subsequent presses activate them.
    }
    revealControls();
    return false;
  }

  bool expandedFromGuide = false;
  bool get liveTvMode => widget.liveTvMode || expandedFromGuide;
  void watchGuidePreview() {
    setState(() {
      expandedFromGuide = true;
      fullscreen = true;
      guideVisible = false;
      controlsVisible = false;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    liveSurfaceFocus.requestFocus();
  }

  bool guideVisible = false;
  bool zapping = false;
  Future<void> zapChannel(int direction) async {
    if (zapping || switchingChannel || widget.loadChannels == null) return;
    zapping = true;
    try {
      final rows = await widget.loadChannels!();
      if (!mounted || rows.isEmpty) return;
      final current = rows.indexWhere(
        (item) => item.id == (liveChannel ?? widget.item)?.id,
      );
      for (var step = 1; step <= rows.length; step++) {
        final item = rows[(current + direction * step) % rows.length];
        if (await switchLiveChannel(item)) break;
      }
    } finally {
      zapping = false;
    }
  }

  Future<void> compactChannels() async {
    if (widget.loadChannels == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: 130,
        padding: const EdgeInsets.all(16),
        color: Colors.black87,
        child: LiveChannelStrip(
          load: widget.loadChannels!,
          currentId: (liveChannel ?? widget.item)?.id,
          autofocus: true,
          onSelect: (item) async {
            if (await switchLiveChannel(item) && sheetContext.mounted) {
              Navigator.pop(sheetContext);
            }
          },
        ),
      ),
    );
    if (mounted) {
      setState(() => controlsVisible = false);
      liveSurfaceFocus.requestFocus();
    }
  }

  void closeGuide() {
    setState(() {
      guideVisible = false;
      if (liveTvMode) controlsVisible = false;
    });
    if (!liveTvMode) {
      revealControls();
    } else {
      liveSurfaceFocus.requestFocus();
    }
  }

  bool showAutoNext = false;
  bool episodeCompleted = false;
  final upNextFocus = FocusNode();
  final upNextScope = FocusScopeNode();
  Duration get upNextDuration {
    if (duration > Duration.zero) return duration;
    // Some providers deliver the episode runtime before the engine knows it.
    final parts =
        currentEpisode?.duration.trim().split(':') ?? const <String>[];
    if (parts.length == 2 || parts.length == 3) {
      final values = parts.map(int.tryParse).toList();
      if (values.every((v) => v != null && v >= 0)) {
        return Duration(
          seconds: values.reversed.indexed.fold<int>(
            0,
            (sum, entry) =>
                sum +
                entry.$2! *
                    (entry.$1 == 0
                        ? 1
                        : entry.$1 == 1
                        ? 60
                        : 3600),
          ),
        );
      }
    }
    return Duration.zero;
  }

  void refreshUpNext() {
    if (!mounted || source.isLive || advancingEpisode) return;
    final length = upNextDuration;
    final nearEnd =
        length > const Duration(seconds: 30) &&
        position >= length - const Duration(seconds: 30);
    final visible =
        nextEpisode != null &&
        !autoNextCancelled &&
        (episodeCompleted || nearEnd);
    final countdown =
        visible &&
        autoplayNext &&
        (episodeCompleted ||
            (length > Duration.zero &&
                position >= length - const Duration(seconds: 15)));
    if (visible != upNextVisible || countdown != showAutoNext) {
      setState(() {
        upNextVisible = visible;
        showAutoNext = countdown;
      });
    }
  }

  void cancelAutoNext() {
    autoNextCancelled = true;
    if (!mounted) return;
    setState(() {
      showAutoNext = false;
      upNextVisible = false;
    });
    revealControls();
    playPauseFocus.requestFocus();
  }

  bool openingSplitScreen = false;
  Future<void> openSplitScreen() async {
    if (openingSplitScreen ||
        !source.isLive ||
        widget.loadChannels == null ||
        widget.resolveChannel == null) {
      return;
    }
    setState(() => openingSplitScreen = true);
    try {
      await liveRecovery?.close();
      await finishLiveRecording();
      await engine.stop();
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
        builder: (_) => LiveMultiviewScreen(
          initialSource: source,
          initialChannel: liveChannel ?? widget.item,
          provider: widget.provider,
          loadChannels: widget.loadChannels!,
          resolveChannel: widget.resolveChannel!,
          engineFactory: widget.engineFactory,
        ),
      );
      await Navigator.of(context).push(route);
      await route.completed;
    } catch (_) {
      recordingMessage('Could not open split screen. Please retry.');
    } finally {
      if (mounted) {
        setupLiveRecovery();
        await start();
        if (mounted) {
          setState(() => openingSplitScreen = false);
          liveSurfaceFocus.requestFocus();
        }
      }
    }
  }

  LiveStreamRecovery? liveRecovery;
  bool reconnectingLive = false;
  void setupLiveRecovery() {
    if (!source.isLive) return;
    liveRecovery = LiveStreamRecovery(
      reconnect: () async {
        await finishLiveRecording();
        await engine.open(source);
      },
      onRecovering: (value) {
        if (mounted) {
          setState(() {
            reconnectingLive = value;
            error = null;
          });
        }
      },
    );
  }

  void setupVideoRecorder() {
    videoRecorder?.removeListener(videoRecordingChanged);
    videoRecorder?.dispose();
    videoRecorder = null;
    final history =
        widget.history ??
        (widget.provider == null
            ? null
            : WatchHistory.forProvider(widget.provider!));
    final item = liveChannel ?? widget.item;
    if (source.uri.scheme == 'file' ||
        history == null ||
        item == null ||
        engine is! VideoRecordingEngine) {
      return;
    }
    videoRecorder = VideoRecorder(
      engine: engine as VideoRecordingEngine,
      store: VideoRecordings.forScope(history.scope),
      item: item,
      title: currentEpisode == null
          ? source.title
          : '${source.title} - ${currentEpisode!.title}',
    );
    videoRecorder!.addListener(videoRecordingChanged);
  }

  Future<void> finishLiveRecording() async {
    final recorder = videoRecorder;
    if (recorder == null) return;
    final active = recorder.recording;
    try {
      await recorder.close();
      if (active) recordingMessage('Recording saved.');
    } catch (_) {
      recordingMessage(
        'Could not save the recording. Check available storage and stream support.',
      );
    }
  }

  VideoRecorder? videoRecorder;
  bool get recordingLocksPlayback =>
      videoRecorder?.recording == true || videoRecorder?.busy == true;
  void videoRecordingChanged() {
    if (mounted) {
      if (recordingLocksPlayback && timelineFocus.hasFocus) {
        playPauseFocus.requestFocus();
      }
      setState(() {
        if (recordingLocksPlayback) {
          dragPosition = null;
          previewTarget = null;
          framePreview = null;
        }
      });
    }
  }

  Future<void> toggleFileRecording() async {
    final recorder = videoRecorder;
    if (recorder == null) return;
    final stopping = recorder.recording;
    try {
      if (!stopping) {
        if (playbackRate != 1) await setPlaybackRate(1);
        if (!playing) await engine.togglePause();
      }
      await recorder.toggle();
      recordingMessage(stopping ? 'Recording saved.' : 'Recording started.');
    } catch (_) {
      recordingMessage(
        'Could not save the recording. Check available storage and stream support.',
      );
    }
  }

  Future<void> togglePlayback() async {
    if (videoRecorder?.recording == true) await toggleFileRecording();
    liveRecovery?.setPaused(playing);
    await engine.togglePause();
  }

  Future<void> closePlayer() async {
    await liveRecovery?.close();
    try {
      await videoRecorder?.close();
    } catch (_) {
      /* Save errors were not reported as successful recordings. */
    }
    videoRecorder?.dispose();
    await engine.dispose();
  }

  Duration get timelineStart => Duration.zero;
  Duration get timelineEnd => duration;

  void recordingMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ),
        );
    }
  }

  PlaybackSource? liveSource;
  PlaybackSource get source => vodSource ?? liveSource ?? widget.source;
  ContentItem? liveChannel;
  bool switchingChannel = false;
  Future<void> chooseChannel() async {
    if (widget.loadChannels == null) return;
    if (liveTvMode) setState(() => controlsVisible = false);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => ChannelPicker(
        liveBrowser: true,
        title: widget.channelCategory,
        load: widget.loadChannels!,
        currentId: (liveChannel ?? widget.item)?.id,
        categoryId: (liveChannel ?? widget.item)?.categoryId,
        provider: widget.provider,
        onSelect: switchLiveChannel,
      ),
    );
    if (mounted) {
      if (!liveTvMode) {
        revealControls();
      } else {
        setState(() => controlsVisible = false);
      }
      liveSurfaceFocus.requestFocus();
    }
  }

  Future<bool> switchLiveChannel(ContentItem selected) async {
    final keepHidden = liveTvMode && !controlsVisible;
    if (widget.provider != null &&
        !await requestTitleAccess(context, widget.provider!, selected)) {
      return false;
    }
    if (!mounted) return false;
    setState(() => switchingChannel = true);
    try {
      final next =
          await (widget.resolveChannel?.call(selected) ??
              widget.provider!.resolvePlayback(selected));
      if (!mounted) return false;
      await liveRecovery?.close();
      await finishLiveRecording();
      if (!mounted) return false;
      setState(() {
        liveSource = next;
        liveChannel = selected;
        error = null;
        starting = true;
      });
      playbackErrorTimer?.cancel();
      playbackProgressVersion++;
      reconnectingLive = false;
      setupVideoRecorder();
      setupLiveRecovery();
      unawaited(checkCatchUp());
      await engine.open(next);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {
          error = source.isLive
              ? null
              : 'Could not play this channel. Please retry.';
          liveRecovery?.failed();
          starting = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => switchingChannel = false);
        if (!keepHidden) revealControls();
      }
    }
    return false;
  }

  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false, fullscreen = false, starting = true;
  double? dragPosition;
  bool controlsVisible = true;
  Timer? controlsTimer;
  Timer? progressTimer;
  bool savedInitialProgress = false;
  Timer? resumeRetry;
  bool resumeReady = false, resumeSeeking = false;
  int resumeAttempts = 0;
  Future<void> verifyResume() async {
    if (!mounted ||
        resumed ||
        !resumeReady ||
        resumeSeeking ||
        resumeAt <= Duration.zero) {
      return;
    }
    if (resumeAttempts >= 6) {
      resumeRetry?.cancel();
      resumed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not resume at the saved position. This stream may not support seeking.',
            ),
          ),
        );
      }
      return;
    }
    resumeSeeking = true;
    resumeAttempts++;
    try {
      await engine.seek(resumeAt).timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Retry after the stream becomes seekable. */
    } finally {
      resumeSeeking = false;
    }
  }

  bool resumed = false;
  bool advancingEpisode = false;
  int seekSeconds = 30;
  double playbackRate = 1;
  Future<void> setPlaybackRate(double rate) async {
    if (recordingLocksPlayback) return;
    try {
      await engine.setRate(rate);
      if (mounted) setState(() => playbackRate = rate);
      await savePlaybackPreferences();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change playback speed. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> savePlaybackPreferences() async {
    final scope = widget.history?.scope;
    if (scope == null) return;
    final display = engine is VideoDisplayEngine
        ? (engine as VideoDisplayEngine).videoDisplay
        : const VideoDisplay();
    try {
      await PlaybackPreferences(scope).save({
        'autoplayNext': autoplayNext,
        'seek': seekSeconds,
        'rate': playbackRate,
        'ratio': display.ratio,
        'zoom': display.zoom,
        'panX': display.pan.dx,
        'panY': display.pan.dy,
      });
    } catch (_) {
      /* Playback keeps running if settings cannot be saved. */
    }
  }

  Future<void> restorePlaybackPreferences() async {
    final scope = widget.history?.scope;
    if (scope == null) return;
    final saved = await PlaybackPreferences(scope).load();
    if (!mounted) return;
    seekSeconds = [10, 20, 30, 60, 120, 180].contains(saved['seek'])
        ? saved['seek']
        : 30;
    autoplayNext = saved['autoplayNext'] == true;
    playbackRate = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 5].contains(saved['rate'])
        ? (saved['rate'] as num).toDouble()
        : 1;
    if (engine is VideoDisplayEngine) {
      // Always open edge-to-edge. Previous letterbox/zoom settings should not
      // make a newly opened stream appear smaller than the screen.
      (engine as VideoDisplayEngine).setVideoDisplay(
        !source.isLive && VideoDisplay.ratios.contains(saved['ratio'])
            ? VideoDisplay(ratio: saved['ratio'])
            : const VideoDisplay(),
      );
    }
    await engine.setRate(playbackRate);
    if (mounted) setState(() {});
  }

  String get seekLabel => seekSeconds == 30
      ? '30 seconds'
      : '${seekSeconds ~/ 60} ${seekSeconds == 60 ? 'minute' : 'minutes'}';
  Future<void> chooseEpisode() async {
    if (widget.episodes.isEmpty) return;
    final history = widget.history != null && widget.item != null
        ? await widget.history!.seriesProgress(widget.item!)
        : <WatchEntry>[];
    if (!mounted) return;
    final selected = await showPlayerDrawer<Episode>(
      context,
      title: 'Episodes',
      builder: (_) => PlayerEpisodeDrawer(
        episodes: widget.episodes,
        current: currentEpisode,
        history: history,
      ),
    );
    if (mounted && selected != null && selected.id != currentEpisode?.id) {
      await switchEpisode(selected);
    }
  }

  String? lastSavedLiveId;
  void rememberLiveChannel() {
    final channel = liveChannel ?? widget.item;
    final provider = widget.provider;
    if (!source.isLive ||
        channel == null ||
        provider == null ||
        channel.id == lastSavedLiveId) {
      return;
    }
    lastSavedLiveId = channel.id;
    unawaited(
      LastLiveChannel.forProvider(provider).save(channel).catchError((
        Object _,
      ) {
        lastSavedLiveId = null;
      }),
    );
  }

  bool catchUpSupported = false;
  int catchUpCheck = 0;
  Future<void> checkCatchUp() async {
    final version = ++catchUpCheck;
    catchUpSupported = false;
    final provider = widget.provider;
    final channel = liveChannel ?? widget.item;
    if (!source.isLive || channel == null || provider is! CatchUpProvider) {
      return;
    }
    try {
      final supported = await (provider as CatchUpProvider).supportsCatchUp(
        channel,
      );
      if (mounted && version == catchUpCheck) {
        setState(() => catchUpSupported = supported);
      }
    } catch (_) {
      // Keep the visible control disabled when availability cannot be confirmed.
    }
  }

  bool openingCatchUp = false;
  Future<void> showCatchUp() async {
    final provider = widget.provider;
    final channel = liveChannel ?? widget.item;
    if (openingCatchUp || provider is! CatchUpProvider || channel == null) {
      return;
    }
    setState(() => openingCatchUp = true);
    var suspended = false;
    try {
      final programme = await showDialog<EpgProgramme>(
        context: context,
        builder: (_) => CatchUpPanel(
          channelName: channel.name,
          load: () => (provider as CatchUpProvider).getCatchUp(channel),
        ),
      );
      if (programme == null || !mounted) return;
      final archive = await (provider as CatchUpProvider).resolveCatchUp(
        channel,
        programme,
      );
      if (!mounted) return;
      await liveRecovery?.close();
      await finishLiveRecording();
      await engine.stop();
      suspended = true;
      if (!mounted) return;
      final route = MaterialPageRoute<void>(
        builder: (_) =>
            PlayerScreen(source: archive, engineFactory: widget.engineFactory),
      );
      await Navigator.of(context).push(route);
      await route.completed;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not play catch-up. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        if (suspended) {
          setupLiveRecovery();
          await start();
        }
        if (mounted) {
          setState(() => openingCatchUp = false);
          revealControls();
        }
      }
    }
  }

  Future<void> showEpg() async {
    if (widget.provider != null) {
      controlsTimer?.cancel();
      setState(() {
        guideVisible = true;
        controlsVisible = false;
      });
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => EpgPanel(
        channelName: source.title,
        load: widget.channelEpg != null && (liveChannel ?? widget.item) != null
            ? () => widget.channelEpg!(liveChannel ?? widget.item!)
            : widget.loadEpg ?? () async => <EpgProgramme>[],
      ),
    );
    if (mounted) revealControls();
  }

  bool skipFinalProgressSave = false;
  FramePreview? framePreview;
  Duration? previewTarget;
  Timer? previewDebounce, previewHide;
  bool fetchingPreview = false;
  bool previewUnavailable = false;
  int previewVersion = 0;

  void requestPreview(Duration target) {
    if (source.isLive || duration <= Duration.zero) return;
    previewVersion++;
    previewDebounce?.cancel();
    previewHide?.cancel();
    setState(() {
      previewTarget = Duration(
        milliseconds: target.inMilliseconds.clamp(
          0,
          duration.inMilliseconds - 1,
        ),
      );
      framePreview = null;
      previewUnavailable = false;
    });
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Keep scrubbing responsive on TV without opening a second video decoder.
      setState(() => previewUnavailable = true);
    } else {
      previewDebounce = Timer(const Duration(milliseconds: 180), fetchPreview);
    }
    previewHide = Timer(const Duration(seconds: 4), () {
      if (mounted && dragPosition == null) {
        setState(() {
          previewTarget = null;
          framePreview = null;
          previewUnavailable = false;
        });
      }
    });
  }

  Future<void> fetchPreview() async {
    if (fetchingPreview ||
        !mounted ||
        previewTarget == null ||
        engine is! FramePreviewEngine) {
      return;
    }
    fetchingPreview = true;
    final version = previewVersion;
    final target = previewTarget!;
    final frame = await (engine as FramePreviewEngine).previewFrame(
      source,
      target,
    );
    fetchingPreview = false;
    if (!mounted) return;
    if (version != previewVersion) {
      if (previewTarget != null) unawaited(fetchPreview());
      return;
    }
    setState(() {
      framePreview = frame;
      previewUnavailable = frame == null;
    });
  }

  String? error;
  Timer? playbackErrorTimer;
  int playbackProgressVersion = 0;
  List<SubtitleOption> subtitleTracks = [];
  String selectedSubtitleName = 'Automatic';
  late final subtitlePreferences = SubtitlePreferences(
    scope: widget.history?.scope,
  );
  String? pendingSubtitle;
  String get subtitleScope =>
      '${widget.history?.scope ?? 'local'}:${widget.item?.type.name ?? 'media'}:${widget.item?.id ?? source.title}:${currentEpisode?.id ?? ''}';
  Future<void> restoreSubtitles() async {
    if (engine is! SubtitleCustomizationEngine) return;
    final custom = engine as SubtitleCustomizationEngine;
    final appearance = await subtitlePreferences.loadAppearance();
    if (!mounted) return;
    custom.setSubtitleAppearance(appearance);
    final choice = await subtitlePreferences.loadChoice(subtitleScope);
    if (!mounted || choice == null) return;
    try {
      if (choice['kind'] == 'online') {
        final key = await SubtitleSettings(scope: widget.history?.scope).load();
        if (key.isEmpty) return;
        final uri = await SubtitleService(
          key,
        ).download(SubtitleResult(choice['fileId'], choice['name']));
        if (!mounted) return;
        await custom.addNamedSubtitle(uri, choice['name']);
      } else if (choice['kind'] == 'url') {
        await custom.addNamedSubtitle(Uri.parse(choice['url']), choice['name']);
      } else {
        final id = choice['id'] as String;
        if (id == 'no' ||
            id == 'auto' ||
            subtitleTracks.any((track) => track.id == id)) {
          await engine.selectSubtitle(id);
        } else {
          pendingSubtitle = id;
          selectedSubtitleId = id;
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not restore the saved subtitle. Use Subtitles to retry or choose another.',
            ),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    guideVisible = widget.initialGuide;
    if (liveTvMode || widget.initialFullscreen || !source.isLive) {
      fullscreen = true;
      controlsVisible = false;
    }
    engine = widget.engineFactory?.call() ?? MediaKitEngine();
    videoSurface = RepaintBoundary(child: engine.surface());
    setupVideoRecorder();
    setupLiveRecovery();
    unawaited(checkCatchUp());
    if (engine is CompletionPlaybackEngine) {
      subscriptions.add(
        (engine as CompletionPlaybackEngine).completed.listen((completed) {
          if (source.isLive && completed) liveRecovery?.failed();
          if (!mounted ||
              source.isLive ||
              nextEpisode == null ||
              advancingEpisode) {
            return;
          }
          setState(() {
            episodeCompleted = completed;
          });
          refreshUpNext();
          if (completed && !autoNextCancelled) {
            setState(() => controlsVisible = true);
          }
        }),
      );
    }
    if (engine is BufferingPlaybackEngine) {
      final progress = engine as BufferingPlaybackEngine;
      subscriptions.add(
        progress.buffering.listen((value) {
          if (mounted) setState(() => buffering = value);
        }),
      );
      subscriptions.add(
        progress.bufferingPercentage.listen((value) {
          if (mounted && value.isFinite) {
            final percent = value.clamp(0, 100).roundToDouble();
            if (bufferPercent != percent) {
              setState(() => bufferPercent = percent);
            }
          }
        }),
      );
    }
    HardwareKeyboard.instance.addHandler(remoteKeys);
    if (engine is SubtitleCustomizationEngine) {
      subscriptions.add(
        (engine as SubtitleCustomizationEngine).selectedSubtitle.listen((name) {
          if (mounted) setState(() => selectedSubtitleName = name);
        }),
      );
    }
    subscriptions.add(
      engine.position.listen((value) {
        if (mounted) {
          liveRecovery?.progress(value);
          if (value != position) {
            playbackProgressVersion++;
            if (error != null) setState(() => error = null);
          }
          position = value;
          refreshUpNext();
          if (!savedInitialProgress &&
              !source.isLive &&
              widget.history != null &&
              duration > Duration.zero &&
              position.inSeconds >= 1 &&
              (resumeAt == Duration.zero || resumed)) {
            savedInitialProgress = true;
            unawaited(saveProgress());
          }
          if (!source.isLive &&
              duration > Duration.zero &&
              value >= duration &&
              videoRecorder?.recording == true &&
              !videoRecorder!.busy) {
            unawaited(toggleFileRecording());
          }
          if (!resumed &&
              resumeAt > Duration.zero &&
              (value - resumeAt).abs() < const Duration(seconds: 3)) {
            resumed = true;
            resumeRetry?.cancel();
          }
          final now = DateTime.now();
          if ((!fullscreen || controlsVisible) &&
              now.difference(lastPositionPaint).inMilliseconds >= 250) {
            lastPositionPaint = now;
            setState(() {});
          }
        }
      }),
    );
    subscriptions.add(
      engine.duration.listen((value) {
        if (mounted) {
          setState(() => duration = value);
          refreshUpNext();
        }
        unawaited(verifyResume());
      }),
    );
    subscriptions.add(
      engine.playing.listen((value) {
        if (value) rememberLiveChannel();
        if (!value && !starting && !buffering) liveRecovery?.failed();
        if (mounted) {
          setState(() {
            playing = value;
            if (value) {
              starting = false;
              error = null;
            }
          });
          if (!source.isLive) revealControls();
        }
      }),
    );
    subscriptions.add(
      engine.errors.listen((value) {
        if (source.isLive) {
          liveRecovery?.failed();
          return;
        }
        playbackErrorTimer?.cancel();
        final reported = playbackProgressVersion;
        // Decoder warnings can occur while live video continues normally.
        // Show an error only if playback fails to make progress afterwards.
        playbackErrorTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted || playbackProgressVersion != reported) return;
          setState(() {
            error = value;
            starting = false;
          });
        });
      }),
    );
    subscriptions.add(
      engine.subtitles.listen((tracks) {
        if (mounted) setState(() => subtitleTracks = tracks);
        if (pendingSubtitle != null &&
            tracks.any((track) => track.id == pendingSubtitle)) {
          final id = pendingSubtitle!;
          pendingSubtitle = null;
          unawaited(engine.selectSubtitle(id));
        }
      }),
    );
    progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(saveProgress()),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        liveTvMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
    if (!liveTvMode) revealControls();
    if (!source.isLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) playPauseFocus.requestFocus();
      });
    }
    if (source.isLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          liveSurfaceFocus.requestFocus();
          if (widget.initialChannelPicker) unawaited(chooseChannel());
        }
      });
    }
    start();
  }

  Future<void> start() async {
    savedInitialProgress = false;
    playbackErrorTimer?.cancel();
    playbackProgressVersion++;
    setState(() {
      error = null;
      starting = true;
    });
    try {
      await engine.open(source);
      resumeReady = true;
      if (resumeAt > Duration.zero && !source.isLive) {
        unawaited(verifyResume());
        resumeRetry?.cancel();
        resumeRetry = Timer.periodic(
          const Duration(seconds: 2),
          (_) => unawaited(verifyResume()),
        );
      }
      if (mounted) await restorePlaybackPreferences();
      if (mounted && !source.isLive) await restoreSubtitles();
    } catch (_) {
      if (mounted) {
        setState(() {
          error = source.isLive
              ? null
              : 'Could not start playback. Please retry.';
          liveRecovery?.failed();
          starting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    upNextScope.dispose();
    upNextFocus.dispose();
    HardwareKeyboard.instance.removeHandler(remoteKeys);
    hiddenSeekTimer?.cancel();
    resumeRetry?.cancel();
    playbackErrorTimer?.cancel();
    timelineFocus.dispose();
    playPauseFocus.dispose();
    liveSurfaceFocus.dispose();
    controlsTimer?.cancel();
    progressTimer?.cancel();
    previewDebounce?.cancel();
    previewHide?.cancel();
    previewVersion++;
    unawaited(saveProgress());
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    videoRecorder?.removeListener(videoRecordingChanged);
    unawaited(closePlayer());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> saveProgress() async {
    if ((resumeAt > Duration.zero && !resumed) ||
        skipFinalProgressSave ||
        source.isLive ||
        widget.history == null ||
        widget.item == null ||
        duration <= Duration.zero) {
      return;
    }
    await widget.history!.save(
      WatchEntry(
        widget.item!,
        currentEpisode,
        position,
        duration,
        DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> seek(Duration target) async {
    if (recordingLocksPlayback) {
      recordingMessage('Stop recording before seeking.');
      return;
    }
    if (source.isLive || duration <= Duration.zero) return;
    final milliseconds = target.inMilliseconds.clamp(
      timelineStart.inMilliseconds,
      timelineEnd.inMilliseconds - 1,
    );
    requestPreview(Duration(milliseconds: milliseconds));
    await engine.seek(Duration(milliseconds: milliseconds));
  }

  Future<void> playNextEpisode() async {
    if (showAutoNext && mounted) setState(() => showAutoNext = false);
    if (videoRecorder?.recording == true) await toggleFileRecording();
    if (nextEpisode != null) await switchEpisode(nextEpisode!);
  }

  Future<void> switchEpisode(Episode selected) async {
    if (advancingEpisode) return;
    setState(() => advancingEpisode = true);
    try {
      if (videoRecorder?.recording == true) await toggleFileRecording();
      final provider = widget.provider;
      if (provider == null || widget.item == null) {
        await saveProgress();
        skipFinalProgressSave = true;
        progressTimer?.cancel();
        await engine.stop();
        if (mounted) Navigator.of(context).pop(selected);
        return;
      }
      final resolved = await provider.resolvePlayback(
        widget.item!,
        episode: selected,
      );
      final saved = await widget.history?.latest(
        widget.item!,
        episode: selected,
      );
      await saveProgress();
      if (!mounted) return;
      resumeRetry?.cancel();
      playbackErrorTimer?.cancel();
      previewDebounce?.cancel();
      previewHide?.cancel();
      previewVersion++;
      setState(() {
        changedEpisode = selected;
        vodSource = resolved;
        changedResume = saved?.position ?? Duration.zero;
        position = Duration.zero;
        duration = Duration.zero;
        resumed = false;
        resumeReady = false;
        resumeAttempts = 0;
        dragPosition = null;
        previewTarget = null;
        framePreview = null;
        pendingSubtitle = null;
        subtitleTracks = [];
        selectedSubtitleName = 'Off';
        showAutoNext = false;
        autoNextCancelled = false;
        selectedSubtitleId = 'auto';
        upNextVisible = false;
        episodeCompleted = false;
      });
      await start();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not switch episodes. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => advancingEpisode = false);
    }
  }

  Future<void> subtitleMenu() async {
    final choice = !source.isLive
        ? await showPlayerOptions(
            context,
            title: 'Subtitles',
            settings: true,
            selected: selectedSubtitleId,
            options: [
              const PlayerOption('no', 'Off'),
              const PlayerOption('auto', 'Automatic'),
              ...playerTrackOptions(
                subtitleTracks
                    .map((track) => (id: track.id, label: track.label))
                    .toList(),
              ),
              const PlayerOption(
                '__url',
                'Add subtitle URL',
                section: 'External Subtitles',
              ),
              const PlayerOption(
                '__online',
                'Search online subtitles',
                section: 'External Subtitles',
              ),
              if (engine is SubtitleCustomizationEngine)
                const PlayerOption(
                  '__style',
                  'Size, color and position',
                  section: 'Appearance',
                ),
            ],
          )
        : await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Subtitles'),
              contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              content: SizedBox(
                width: 280,
                height: 240,
                child: StreamBuilder<List<SubtitleOption>>(
                  stream: engine.subtitles,
                  initialData: subtitleTracks,
                  builder: (_, snapshot) => ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: const Icon(Icons.add),
                        title: const Text('Add subtitle URL'),
                        onTap: () => Navigator.pop(context, '__url'),
                      ),
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: const Icon(Icons.search),
                        title: const Text('Search online subtitles'),
                        onTap: () => Navigator.pop(context, '__online'),
                      ),
                      if (engine is SubtitleCustomizationEngine) ...[
                        StreamBuilder<String>(
                          stream: (engine as SubtitleCustomizationEngine)
                              .selectedSubtitle,
                          builder: (_, snapshot) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              'Selected: ${snapshot.data ?? selectedSubtitleName}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: const Icon(Icons.format_size),
                          title: const Text('Size, color and position'),
                          onTap: () => Navigator.pop(context, '__style'),
                        ),
                      ],
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Off'),
                        onTap: () => Navigator.pop(context, 'no'),
                      ),
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: const Text('Automatic'),
                        onTap: () => Navigator.pop(context, 'auto'),
                      ),
                      if ((snapshot.data ?? []).isEmpty)
                        const ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text('No IPTV subtitle tracks detected.'),
                        ),
                      for (final track in snapshot.data ?? <SubtitleOption>[])
                        ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(track.label),
                          onTap: () => Navigator.pop(context, track.id),
                        ),
                      const Divider(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
    if (!mounted || choice == null) return;
    if (choice == '__style' && engine is SubtitleCustomizationEngine) {
      await showDialog<void>(
        context: context,
        builder: (_) => SubtitleAppearanceDialog(
          engine: engine as SubtitleCustomizationEngine,
        ),
      );
      if (engine is SubtitleCustomizationEngine) {
        await subtitlePreferences.saveAppearance(
          (engine as SubtitleCustomizationEngine).subtitleAppearance,
        );
      }
      return;
    }
    if (choice == '__online') {
      final savedChoice = await subtitlePreferences.loadChoice(subtitleScope);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => OnlineSubtitleDialog(
          selectedFileId:
              savedChoice?['kind'] == 'online' &&
                  savedChoice?['fileId'] is int &&
                  savedChoice?['name'] == selectedSubtitleName
              ? savedChoice!['fileId'] as int
              : null,
          title: source.title,
          engine: engine,
          scope: widget.history?.scope,
          onSelected: (result) => subtitlePreferences.saveChoice(
            subtitleScope,
            {'kind': 'online', 'fileId': result.fileId, 'name': result.label},
          ),
        ),
      );
      return;
    }
    try {
      if (choice == '__url') {
        final controller = TextEditingController();
        final link = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Add subtitle URL'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://example.com/subtitles.srt',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Add'),
              ),
            ],
          ),
        );
        // Wait for the dialog animation before disposing its text controller.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        controller.dispose();
        if (!mounted || link == null) return;
        final uri = Uri.tryParse(link);
        if (uri == null ||
            !['https', 'http'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw const ProviderException(
            'Enter a valid HTTP or HTTPS subtitle URL.',
          );
        }
        await engine.addSubtitle(uri);
        await subtitlePreferences.saveChoice(subtitleScope, {
          'kind': 'url',
          'url': uri.toString(),
          'name': uri.pathSegments.isEmpty
              ? 'External subtitle'
              : uri.pathSegments.last,
        });
      } else {
        await engine.selectSubtitle(choice);
        if (mounted) setState(() => selectedSubtitleId = choice);
        if (engine is SubtitleCustomizationEngine) {
          await subtitlePreferences.saveChoice(subtitleScope, {
            'kind': 'track',
            'id': choice,
          });
        }
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              exception is ProviderException
                  ? exception.message
                  : 'Could not load the subtitles. Please retry.',
            ),
          ),
        );
      }
    }
  }

  void toggleFullscreen() {
    controlsTimer?.cancel();
    setState(() {
      fullscreen = !fullscreen;
      controlsVisible = !fullscreen;
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  bool exitingPlayer = false;
  Future<void> exitPlayer() async {
    if (exitingPlayer || !mounted) return;
    controlsTimer?.cancel();
    setState(() => exitingPlayer = true);
    // Let PopScope enable popping before the explicit Back action.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await Navigator.of(context).maybePop();
    if (mounted) setState(() => exitingPlayer = false);
  }

  void handlePlayerBack() {
    if (!source.isLive && dragPosition != null) {
      hiddenSeekTimer?.cancel();
      setState(() {
        dragPosition = null;
        previewTarget = null;
        framePreview = null;
      });
      revealControls();
      return;
    }
    if (guideVisible) {
      closeGuide();
    } else if (showAutoNext || upNextVisible) {
      cancelAutoNext();
    } else if (liveTvMode && source.isLive && controlsVisible) {
      controlsTimer?.cancel();
      setState(() => controlsVisible = false);
      liveSurfaceFocus.requestFocus();
    } else if (controlsVisible) {
      controlsTimer?.cancel();
      setState(() => controlsVisible = false);
      if (source.isLive) liveSurfaceFocus.requestFocus();
    } else if (liveTvMode && source.isLive) {
      unawaited(exitPlayer());
    } else {
      unawaited(exitPlayer());
    }
  }

  bool liveMuted = false;

  void revealControls() {
    if (guideVisible) return;
    controlsTimer?.cancel();
    if (!controlsVisible) setState(() => controlsVisible = true);
    if (!source.isLive && (vodDrawerOpen || !playing || dragPosition != null)) {
      return;
    }
    if (!fullscreen && !source.isLive) return;
    controlsTimer = Timer(Duration(seconds: source.isLive ? 15 : 5), () {
      if (mounted &&
          (fullscreen || source.isLive) &&
          (source.isLive ||
              (playing && !vodDrawerOpen && dragPosition == null))) {
        setState(() => controlsVisible = false);
      }
    });
  }

  String time(Duration value) {
    final seconds = value.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    final hours = seconds ~/ 3600;
    return '${hours > 0 ? '$hours:' : ''}${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  double lastSubtitleInset = -1;
  @override
  Widget build(BuildContext context) {
    if (engine is SubtitleOverlayAvoidanceEngine) {
      final inset = !source.isLive && controlsVisible && !vodDrawerOpen
          ? VodPlayerControls.overlayHeightFor(
                  MediaQuery.sizeOf(context).height,
                ) +
                12
          : 0.0;
      if (inset != lastSubtitleInset) {
        lastSubtitleInset = inset;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            (engine as SubtitleOverlayAvoidanceEngine).setSubtitleBottomInset(
              inset,
            );
          }
        });
      }
    }
    return TooltipVisibility(visible: false, child: buildPlayer(context));
  }

  Widget buildPlayer(BuildContext context) => PopScope(
    canPop:
        exitingPlayer ||
        (!liveTvMode &&
            !controlsVisible &&
            !showAutoNext &&
            !upNextVisible &&
            !guideVisible),
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        // Capture progress before shutdown events and before the details page resumes.
        progressTimer?.cancel();
        unawaited(saveProgress());
        skipFinalProgressSave = true;
      } else {
        handlePlayerBack();
      }
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => togglePlayback(),
        if (source.isLive)
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
              togglePlayback(),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () =>
            seek(position + Duration(seconds: seekSeconds)),
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () =>
            seek(position - Duration(seconds: seekSeconds)),
        if (source.isLive)
          const SingleActivator(LogicalKeyboardKey.escape): handlePlayerBack,
        if (source.isLive)
          const SingleActivator(LogicalKeyboardKey.goBack): handlePlayerBack,
      },
      child: Focus(
        focusNode: liveSurfaceFocus,
        canRequestFocus: source.isLive,
        child: Scaffold(
          backgroundColor: const Color(0xff090b13),
          appBar: fullscreen || !controlsVisible || guideVisible
              ? null
              : AppBar(
                  leading: BackButton(
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: Text(
                    source.title,
                    style: const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  backgroundColor: const Color(0xff101322),
                ),
          body: SafeArea(
            top: !fullscreen,
            bottom: !fullscreen,
            left: !fullscreen,
            right: !fullscreen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: guideVisible ? 16 : 0,
                        top: guideVisible
                            ? MediaQuery.paddingOf(context).top + 60
                            : 0,
                        right: guideVisible ? null : 0,
                        bottom: guideVisible ? null : 0,
                        width: guideVisible
                            ? (MediaQuery.sizeOf(context).width * .30).clamp(
                                160,
                                350,
                              )
                            : null,
                        height: guideVisible ? 136 : null,
                        child: MouseRegion(
                          onHover: (_) => revealControls(),
                          cursor: fullscreen && !controlsVisible
                              ? SystemMouseCursors.none
                              : MouseCursor.defer,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: revealControls,
                            child: videoSurface,
                          ),
                        ),
                      ),
                      if (videoRecorder?.recording == true)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.fiber_manual_record,
                                  color: Colors.redAccent,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Recording in progress',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if ((starting || buffering || reconnectingLive) &&
                          error == null)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  value:
                                      source.isLive ||
                                          bufferPercent == null ||
                                          bufferPercent == 0
                                      ? null
                                      : bufferPercent! / 100,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  reconnectingLive
                                      ? 'Reconnecting channel...'
                                      : starting
                                      ? 'Loading ${source.isLive ? "channel" : "video"}...'
                                      : 'Buffering...',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (!source.isLive && bufferPercent != null)
                                  Text(
                                    'Buffer ${bufferPercent!.round()}%',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
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
                if (!source.isLive &&
                    controlsVisible &&
                    dragPosition != null &&
                    framePreview != null)
                  Positioned(
                    bottom: 285,
                    left: 28,
                    child: SizedBox(
                      width: 208,
                      height: 118,
                      child: Image.memory(
                        framePreview!.image,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                if (!source.isLive)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: VodPlayerControls(
                      title: widget.item?.name ?? source.title,
                      metadata: currentEpisode != null
                          ? 'S${currentEpisode!.season} E${currentEpisode!.number} \u00b7 ${currentEpisode!.title}'
                          : [
                              if (widget.item?.releaseYear != null)
                                '${widget.item!.releaseYear}'
                              else if ((widget.metadata?.releaseDate ?? '')
                                      .length >=
                                  4)
                                widget.metadata!.releaseDate.substring(0, 4),
                              widget.metadata?.genre ?? '',
                            ].where((s) => s.isNotEmpty).join(' \u00b7 '),
                      position:
                          dragPosition ?? position.inMilliseconds.toDouble(),
                      duration: duration.inMilliseconds.toDouble(),
                      positionLabel: time(
                        dragPosition == null
                            ? position
                            : Duration(milliseconds: dragPosition!.toInt()),
                      ),
                      durationLabel: time(duration),
                      visible: controlsVisible && !vodDrawerOpen,
                      playing: playing,
                      seekEnabled:
                          !recordingLocksPlayback && duration > Duration.zero,
                      seeking: dragPosition != null,
                      playFocus: playPauseFocus,
                      seekFocus: timelineFocus,
                      onActivity: revealControls,
                      onPlay: togglePlayback,
                      onRewind: () =>
                          seek(position - const Duration(seconds: 10)),
                      onForward: () =>
                          seek(position + const Duration(seconds: 10)),
                      onPrevious: previousEpisode == null || advancingEpisode
                          ? null
                          : () => switchEpisode(previousEpisode!),
                      onNext: nextEpisode == null || advancingEpisode
                          ? null
                          : playNextEpisode,
                      onEpisodes: widget.episodes.isEmpty
                          ? null
                          : () => vodOverlay(chooseEpisode),
                      onAudio: engine is AudioTrackPlaybackEngine
                          ? () => vodOverlay(audioMenu)
                          : null,
                      onSubtitles: () => vodOverlay(subtitleMenu),
                      onMore: () => vodOverlay(vodMore),
                      onSeekChanged: (value) {
                        controlsTimer?.cancel();
                        setState(() => dragPosition = value);
                      },
                      onSeekEnd: (value) {
                        unawaited(seek(Duration(milliseconds: value.toInt())));
                        setState(() => dragPosition = null);
                        revealControls();
                      },
                    ),
                  ),
                if (controlsVisible && !liveTvMode && source.isLive)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (previewTarget != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: Container(
                                width: 220,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white54),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 118,
                                      width: 208,
                                      child: framePreview != null
                                          ? Image.memory(
                                              framePreview!.image,
                                              fit: BoxFit.contain,
                                              gaplessPlayback: true,
                                            )
                                          : Center(
                                              child: Text(
                                                previewUnavailable
                                                    ? 'Preview unavailable'
                                                    : 'Loading preview…',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      time(
                                        framePreview?.position ??
                                            previewTarget!,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Container(
                          color: const Color(0xdd15192a),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              iconTheme: const IconThemeData(
                                size: 18,
                                color: Colors.white70,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              iconButtonTheme: IconButtonThemeData(
                                style:
                                    (Theme.of(context).iconButtonTheme.style ??
                                            const ButtonStyle())
                                        .copyWith(
                                          iconSize:
                                              const WidgetStatePropertyAll(18),
                                          minimumSize:
                                              const WidgetStatePropertyAll(
                                                Size(36, 36),
                                              ),
                                          padding: const WidgetStatePropertyAll(
                                            EdgeInsets.all(6),
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                              ),
                              filledButtonTheme: FilledButtonThemeData(
                                style:
                                    (Theme.of(
                                              context,
                                            ).filledButtonTheme.style ??
                                            const ButtonStyle())
                                        .copyWith(
                                          minimumSize:
                                              const WidgetStatePropertyAll(
                                                Size(36, 36),
                                              ),
                                          padding: const WidgetStatePropertyAll(
                                            EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                          ),
                                          iconSize:
                                              const WidgetStatePropertyAll(18),
                                        ),
                              ),
                              sliderTheme: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                              ),
                              textTheme: Theme.of(
                                context,
                              ).textTheme.apply(fontSizeFactor: 0.9),
                            ),
                            child: Column(
                              children: [
                                if (!source.isLive && widget.initialFullscreen)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        source.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (!source.isLive)
                                  Row(
                                    children: [
                                      Text(
                                        time(
                                          Duration(
                                            milliseconds:
                                                (dragPosition ??
                                                        position.inMilliseconds
                                                            .toDouble())
                                                    .toInt(),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          focusNode: timelineFocus,
                                          min: timelineStart.inMilliseconds
                                              .toDouble(),
                                          max: timelineEnd.inMilliseconds > 0
                                              ? timelineEnd.inMilliseconds
                                                    .toDouble()
                                              : 1,
                                          value:
                                              (dragPosition ??
                                                      position.inMilliseconds
                                                          .toDouble())
                                                  .clamp(
                                                    timelineStart.inMilliseconds
                                                        .toDouble(),
                                                    timelineEnd.inMilliseconds >
                                                            0
                                                        ? timelineEnd
                                                              .inMilliseconds
                                                              .toDouble()
                                                        : 1,
                                                  ),
                                          onChangeStart:
                                              recordingLocksPlayback ||
                                                  duration <= Duration.zero
                                              ? null
                                              : (value) {
                                                  setState(
                                                    () => dragPosition = value,
                                                  );
                                                  requestPreview(
                                                    Duration(
                                                      milliseconds: value
                                                          .toInt(),
                                                    ),
                                                  );
                                                },
                                          onChanged:
                                              recordingLocksPlayback ||
                                                  duration <= Duration.zero
                                              ? null
                                              : (value) {
                                                  setState(
                                                    () => dragPosition = value,
                                                  );
                                                  requestPreview(
                                                    Duration(
                                                      milliseconds: value
                                                          .toInt(),
                                                    ),
                                                  );
                                                },
                                          onChangeEnd:
                                              recordingLocksPlayback ||
                                                  duration <= Duration.zero
                                              ? null
                                              : (value) {
                                                  seek(
                                                    Duration(
                                                      milliseconds: value
                                                          .toInt(),
                                                    ),
                                                  );
                                                  setState(
                                                    () => dragPosition = null,
                                                  );
                                                },
                                        ),
                                      ),
                                      Text(time(timelineEnd)),
                                    ],
                                  ),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final mainControls = Focus(
                                      canRequestFocus: false,
                                      onKeyEvent: liveControlKeys,
                                      child: FocusTraversalGroup(
                                        policy: ReadingOrderTraversalPolicy(),
                                        child: Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 4,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            if (source.isLive &&
                                                widget.loadChannels != null &&
                                                widget.resolveChannel != null)
                                              IconButton(
                                                tooltip: 'Channels',
                                                icon: const ChannelListIcon(),
                                                onPressed: switchingChannel
                                                    ? null
                                                    : chooseChannel,
                                              ),

                                            if (source.isLive)
                                              IconButton(
                                                tooltip: 'Programme guide',
                                                icon: const Icon(
                                                  Icons.view_list_outlined,
                                                ),
                                                onPressed: showEpg,
                                              ),
                                            if (source.isLive &&
                                                widget.loadChannels != null &&
                                                widget.resolveChannel != null &&
                                                engine is AudioPlaybackEngine)
                                              IconButton(
                                                tooltip: 'Split screen',
                                                icon: const Icon(
                                                  Icons.splitscreen_outlined,
                                                ),
                                                onPressed: openingSplitScreen
                                                    ? null
                                                    : openSplitScreen,
                                              ),
                                            if (source.isLive)
                                              LiveHealthIndicator(
                                                position: position,
                                                playing: playing,
                                                starting: starting,
                                                buffering: buffering,
                                                reconnecting: reconnectingLive,
                                              ),
                                            if (source.isLive)
                                              IconButton(
                                                tooltip: catchUpSupported
                                                    ? 'Catch-up'
                                                    : 'Catch-up unavailable for this channel',
                                                disabledColor: Colors.white30,
                                                icon: const Icon(Icons.history),
                                                onPressed:
                                                    openingCatchUp ||
                                                        !catchUpSupported
                                                    ? null
                                                    : showCatchUp,
                                              ),
                                            if (!source.isLive)
                                              SizedBox(
                                                key: const ValueKey(
                                                  'seek-control',
                                                ),
                                                width: 84,
                                                height: 36,
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 28,
                                                      child: IconButton(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 28,
                                                              minHeight: 36,
                                                            ),
                                                        tooltip:
                                                            'Rewind $seekLabel',
                                                        icon: const Icon(
                                                          Icons.fast_rewind,
                                                          size: 18,
                                                        ),
                                                        onPressed:
                                                            recordingLocksPlayback
                                                            ? null
                                                            : () => seek(
                                                                position -
                                                                    Duration(
                                                                      seconds:
                                                                          seekSeconds,
                                                                    ),
                                                              ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 28,
                                                      height: 36,
                                                      child: PopupMenuButton<int>(
                                                        tooltip:
                                                            'Seek interval',
                                                        enabled:
                                                            !recordingLocksPlayback,
                                                        initialValue:
                                                            seekSeconds,
                                                        onSelected: (value) {
                                                          if (recordingLocksPlayback) {
                                                            return;
                                                          }
                                                          setState(
                                                            () => seekSeconds =
                                                                value,
                                                          );
                                                          unawaited(
                                                            savePlaybackPreferences(),
                                                          );
                                                        },
                                                        itemBuilder: (_) =>
                                                            const [
                                                              PopupMenuItem(
                                                                value: 30,
                                                                child: Text(
                                                                  '30 seconds',
                                                                ),
                                                              ),
                                                              PopupMenuItem(
                                                                value: 60,
                                                                child: Text(
                                                                  '1 minute',
                                                                ),
                                                              ),
                                                              PopupMenuItem(
                                                                value: 120,
                                                                child: Text(
                                                                  '2 minutes',
                                                                ),
                                                              ),
                                                              PopupMenuItem(
                                                                value: 180,
                                                                child: Text(
                                                                  '3 minutes',
                                                                ),
                                                              ),
                                                            ],
                                                        child: Center(
                                                          child: FittedBox(
                                                            fit: BoxFit
                                                                .scaleDown,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .timer_outlined,
                                                                  size: 18,
                                                                ),
                                                                const Icon(
                                                                  Icons
                                                                      .arrow_drop_down,
                                                                  size: 16,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 28,
                                                      child: IconButton(
                                                        padding:
                                                            EdgeInsets.zero,
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 28,
                                                              minHeight: 36,
                                                            ),
                                                        tooltip:
                                                            'Forward $seekLabel',
                                                        icon: const Icon(
                                                          Icons.fast_forward,
                                                          size: 18,
                                                        ),
                                                        onPressed:
                                                            recordingLocksPlayback
                                                            ? null
                                                            : () => seek(
                                                                position +
                                                                    Duration(
                                                                      seconds:
                                                                          seekSeconds,
                                                                    ),
                                                              ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (!source.isLive)
                                              SizedBox(
                                                key: const ValueKey(
                                                  'speed-control',
                                                ),
                                                width: 36,
                                                height: 36,
                                                child: PopupMenuButton<double>(
                                                  tooltip: 'Playback speed',
                                                  enabled:
                                                      !recordingLocksPlayback,
                                                  initialValue: playbackRate,
                                                  onSelected: setPlaybackRate,
                                                  itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                      value: 1,
                                                      child: Text('Normal'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 0.5,
                                                      child: Text('0.5×'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 2,
                                                      child: Text('2×'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 3,
                                                      child: Text('3×'),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 5,
                                                      child: Text('5×'),
                                                    ),
                                                  ],
                                                  child: Icon(
                                                    Icons.speed,
                                                    color:
                                                        recordingLocksPlayback
                                                        ? Colors.white30
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                            SizedBox(
                                              key: const ValueKey(
                                                'play-pause-control',
                                              ),
                                              width: 36,
                                              height: 36,
                                              child: IconButton(
                                                autofocus: !source.isLive,
                                                focusNode: playPauseFocus,
                                                style: ButtonStyle(
                                                  backgroundColor:
                                                      const WidgetStatePropertyAll(
                                                        Colors.transparent,
                                                      ),
                                                  foregroundColor:
                                                      WidgetStateProperty.resolveWith(
                                                        (states) =>
                                                            states.contains(
                                                              WidgetState
                                                                  .focused,
                                                            )
                                                            ? Colors.white
                                                            : Colors.white70,
                                                      ),
                                                  overlayColor:
                                                      const WidgetStatePropertyAll(
                                                        Colors.white12,
                                                      ),
                                                ),
                                                tooltip: playing
                                                    ? 'Pause'
                                                    : 'Play',
                                                onPressed: togglePlayback,
                                                icon: Icon(
                                                  playing
                                                      ? Icons.pause
                                                      : Icons.play_arrow,
                                                ),
                                              ),
                                            ),
                                            if (engine
                                                is VideoDisplayEngine) ...[
                                              IconButton(
                                                tooltip: 'Aspect ratio',
                                                icon: const Icon(
                                                  Icons.aspect_ratio,
                                                ),
                                                onPressed: () async {
                                                  await showDialog<void>(
                                                    context: context,
                                                    builder: (_) =>
                                                        VideoDisplayDialog(
                                                          engine:
                                                              engine
                                                                  as VideoDisplayEngine,
                                                        ),
                                                  );
                                                  await savePlaybackPreferences();
                                                },
                                              ),
                                            ],
                                            if (source.isLive) ...[
                                              if (widget.provider != null &&
                                                  (liveChannel ??
                                                          widget.item) !=
                                                      null)
                                                MyListButton(
                                                  key: ValueKey(
                                                    (liveChannel ??
                                                            widget.item)!
                                                        .id,
                                                  ),
                                                  provider: widget.provider!,
                                                  item:
                                                      (liveChannel ??
                                                      widget.item)!,
                                                ),
                                            ],
                                            if (videoRecorder != null)
                                              IconButton(
                                                tooltip:
                                                    videoRecorder!.recording
                                                    ? 'Stop recording'
                                                    : 'Record',
                                                color: Colors.redAccent,
                                                disabledColor: Colors.redAccent
                                                    .withValues(alpha: .35),
                                                onPressed:
                                                    videoRecorder!.busy ||
                                                        starting ||
                                                        reconnectingLive ||
                                                        switchingChannel
                                                    ? null
                                                    : toggleFileRecording,
                                                icon: Icon(
                                                  videoRecorder!.recording
                                                      ? Icons.stop_circle
                                                      : Icons
                                                            .fiber_manual_record,
                                                ),
                                              ),
                                            if (!source.isLive)
                                              IconButton(
                                                tooltip: 'Subtitles',
                                                onPressed: subtitleMenu,
                                                icon: const Icon(
                                                  Icons.subtitles_outlined,
                                                ),
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
                                            if (source.isLive)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  left: 12,
                                                ),
                                                child: Text(
                                                  '● LIVE',
                                                  style: TextStyle(
                                                    color: Colors.redAccent,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                    final episodeControls = Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (nextEpisode != null)
                                            FilledButton.tonalIcon(
                                              onPressed: advancingEpisode
                                                  ? null
                                                  : playNextEpisode,
                                              icon: const Icon(Icons.skip_next),
                                              label: Text(
                                                advancingEpisode
                                                    ? 'Preparing…'
                                                    : 'Next episode',
                                              ),
                                            ),
                                          if (widget.episodes.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Episodes',
                                              icon: const Icon(
                                                Icons.playlist_play,
                                              ),
                                              onPressed: advancingEpisode
                                                  ? null
                                                  : chooseEpisode,
                                            ),
                                        ],
                                      ),
                                    );
                                    final hasRightControls =
                                        nextEpisode != null ||
                                        widget.episodes.isNotEmpty;
                                    if (constraints.maxWidth < 650 &&
                                        hasRightControls) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          mainControls,
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: episodeControls,
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Expanded(child: mainControls),
                                        if (hasRightControls) episodeControls,
                                      ],
                                    );
                                  },
                                ),
                                if (source.isLive &&
                                    (widget.loadEpg != null ||
                                        widget.channelEpg != null))
                                  LiveNowPlaying(
                                    key: ValueKey(
                                      (liveChannel ?? widget.item)?.id ??
                                          source.title,
                                    ),
                                    load:
                                        widget.channelEpg != null &&
                                            (liveChannel ?? widget.item) != null
                                        ? () => widget.channelEpg!(
                                            liveChannel ?? widget.item!,
                                          )
                                        : widget.loadEpg ??
                                              () async => <EpgProgramme>[],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!source.isLive &&
                    (upNextVisible || showAutoNext) &&
                    nextEpisode != null)
                  Positioned(
                    right: 24,
                    bottom: controlsVisible
                        ? VodPlayerControls.overlayHeightFor(
                                MediaQuery.sizeOf(context).height,
                              ) +
                              12
                        : 24,
                    child: Offstage(
                      offstage: vodDrawerOpen || dragPosition != null,
                      child: FocusScope(
                        node: upNextScope,
                        child: NextEpisodeCountdown(
                          key: ValueKey(nextEpisode!.id),
                          episode: nextEpisode!,
                          seriesTitle: widget.item?.name,
                          artwork: widget.seriesArtwork ?? widget.item?.artwork,
                          playFocus: upNextFocus,
                          countdown: showAutoNext,
                          paused:
                              vodDrawerOpen ||
                              dragPosition != null ||
                              advancingEpisode ||
                              (!playing && !episodeCompleted),
                          onPlay: () {
                            unawaited(playNextEpisode());
                          },
                          onCancel: cancelAutoNext,
                          onEpisodes: episodeCompleted && !showAutoNext
                              ? chooseEpisode
                              : null,
                        ),
                      ),
                    ),
                  ),
                if (liveTvMode && controlsVisible && !guideVisible) ...[
                  Positioned(
                    top: 18,
                    left: 24,
                    right: 24,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to dashboard',
                          onPressed: exitPlayer,
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.channelCategory,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SystemClock(),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Focus(
                      canRequestFocus: false,
                      onKeyEvent: liveControlKeys,
                      child: FocusTraversalGroup(
                        policy: ReadingOrderTraversalPolicy(),
                        child: LiveTvControls(
                          key: ValueKey((liveChannel ?? widget.item)?.id),
                          channel: liveChannel ?? widget.item,
                          title: source.title,
                          provider: widget.provider,
                          loadGuide: () =>
                              widget.channelEpg != null &&
                                  (liveChannel ?? widget.item) != null
                              ? widget.channelEpg!(liveChannel ?? widget.item!)
                              : widget.loadEpg?.call() ??
                                    Future.value(<EpgProgramme>[]),
                          loadChannels: widget.loadChannels,
                          onSwitch: (item) async {
                            await switchLiveChannel(item);
                          },
                          onChannels: chooseChannel,
                          onGuide: showEpg,
                          onActivity: revealControls,
                          onOverlayOpened: () => controlsTimer?.cancel(),
                          onAspect: engine is VideoDisplayEngine
                              ? () async {
                                  controlsTimer?.cancel();
                                  await showDialog<void>(
                                    context: context,
                                    builder: (_) => VideoDisplayDialog(
                                      engine: engine as VideoDisplayEngine,
                                    ),
                                  );
                                  await savePlaybackPreferences();
                                  if (mounted) revealControls();
                                }
                              : null,
                          muted: liveMuted,
                          onVolume: engine is AudioPlaybackEngine
                              ? () async {
                                  final muted = !liveMuted;
                                  await (engine as AudioPlaybackEngine)
                                      .setVolume(muted ? 0 : 100);
                                  if (mounted) {
                                    setState(() => liveMuted = muted);
                                  }
                                }
                              : null,
                          onRecord:
                              videoRecorder == null ||
                                  videoRecorder!.busy ||
                                  starting ||
                                  switchingChannel
                              ? null
                              : toggleFileRecording,
                          onCatchUp: catchUpSupported ? showCatchUp : null,
                          onSplit:
                              widget.loadChannels != null &&
                                  widget.resolveChannel != null &&
                                  engine is AudioPlaybackEngine
                              ? openSplitScreen
                              : null,
                          health: LiveHealthIndicator(
                            position: position,
                            playing: playing,
                            starting: starting,
                            buffering: buffering,
                            reconnecting: reconnectingLive,
                          ),
                          playing: playing,
                          recording: videoRecorder?.recording ?? false,
                          primaryFocus: playPauseFocus,
                        ),
                      ),
                    ),
                  ),
                ],
                if (guideVisible && widget.provider != null)
                  Positioned.fill(
                    child: TvGuideScreen(
                      provider: widget.provider!,
                      activePreview: true,
                      previewChannel: liveChannel ?? widget.item,
                      previewLoading: starting || buffering || reconnectingLive,
                      onTune: switchLiveChannel,
                      onWatchPreview: watchGuidePreview,
                      onClose: () {
                        closeGuide();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
