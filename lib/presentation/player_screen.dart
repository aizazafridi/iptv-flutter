import '../application/video_recorder.dart';
import '../data/video_recordings.dart';
import '../playback/video_recording_engine.dart';
import 'title_access.dart';
import 'next_episode_countdown.dart';
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
import 'episode_picker.dart';
import 'epg_panel.dart';
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
  final PlaybackSource source;
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
        playPauseFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  DateTime lastPositionPaint = DateTime.fromMillisecondsSinceEpoch(0);
  bool remoteKeys(KeyEvent event) {
    if (!mounted || event is KeyUpEvent || showAutoNext) return false;
    final key = event.logicalKey;
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
    if (source.isLive && liveSurfaceFocus.hasPrimaryFocus) {
      revealControls();
      playPauseFocus.requestFocus();
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

  bool showAutoNext = false;
  void cancelAutoNext() {
    if (!mounted) return;
    setState(() => showAutoNext = false);
    revealControls();
    playPauseFocus.requestFocus();
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
      title: widget.episode == null
          ? source.title
          : '${source.title} - ${widget.episode!.title}',
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
  PlaybackSource get source => liveSource ?? widget.source;
  ContentItem? liveChannel;
  bool switchingChannel = false;
  Future<void> chooseChannel() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => ChannelPicker(
        title: widget.channelCategory,
        load: widget.loadChannels!,
        currentId: (liveChannel ?? widget.item)?.id,
        categoryId: (liveChannel ?? widget.item)?.categoryId,
        provider: widget.provider,
        onSelect: switchLiveChannel,
      ),
    );
    if (mounted) {
      revealControls();
      liveSurfaceFocus.requestFocus();
    }
  }

  Future<bool> switchLiveChannel(ContentItem selected) async {
    if (widget.provider != null &&
        !await requestTitleAccess(context, widget.provider!, selected)) {
      return false;
    }
    if (!mounted) return false;
    setState(() => switchingChannel = true);
    try {
      final next = await widget.resolveChannel!(selected);
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
        revealControls();
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
  Timer? resumeRetry;
  bool resumeReady = false, resumeSeeking = false;
  int resumeAttempts = 0;
  Future<void> verifyResume() async {
    if (!mounted ||
        resumed ||
        !resumeReady ||
        resumeSeeking ||
        widget.resumeAt <= Duration.zero) {
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
      await engine.seek(widget.resumeAt).timeout(const Duration(seconds: 3));
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
    seekSeconds = [30, 60, 120, 180].contains(saved['seek'])
        ? saved['seek']
        : 30;
    playbackRate = [0.5, 1, 2, 3, 5].contains(saved['rate'])
        ? (saved['rate'] as num).toDouble()
        : 1;
    if (engine is VideoDisplayEngine) {
      // Always open edge-to-edge. Previous letterbox/zoom settings should not
      // make a newly opened stream appear smaller than the screen.
      (engine as VideoDisplayEngine).setVideoDisplay(const VideoDisplay());
    }
    await engine.setRate(playbackRate);
    if (mounted) setState(() {});
  }

  String get seekLabel => seekSeconds == 30
      ? '30 seconds'
      : '${seekSeconds ~/ 60} ${seekSeconds == 60 ? 'minute' : 'minutes'}';
  Future<void> chooseEpisode() async {
    if (videoRecorder?.recording == true) await toggleFileRecording();
    if (!mounted) return;
    final selected = await showDialog<Episode>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => EpisodePicker(
        episodes: widget.episodes,
        currentId: widget.episode?.id,
        fallbackArtwork: widget.seriesArtwork ?? widget.item?.artwork,
      ),
    );
    if (mounted && selected != null && selected.id != widget.episode?.id) {
      await switchEpisode(selected);
    }
  }

  Future<void> showEpg() async {
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
      '${widget.history?.scope ?? 'local'}:${widget.item?.type.name ?? 'media'}:${widget.item?.id ?? source.title}:${widget.episode?.id ?? ''}';
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
    engine = widget.engineFactory?.call() ?? MediaKitEngine();
    videoSurface = RepaintBoundary(child: engine.surface());
    setupVideoRecorder();
    setupLiveRecovery();
    if (engine is CompletionPlaybackEngine) {
      subscriptions.add(
        (engine as CompletionPlaybackEngine).completed.listen((completed) {
          if (source.isLive && completed) liveRecovery?.failed();
          if (!mounted ||
              source.isLive ||
              widget.nextEpisode == null ||
              advancingEpisode) {
            return;
          }
          setState(() => showAutoNext = completed);
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
          if (!source.isLive &&
              duration > Duration.zero &&
              value >= duration &&
              videoRecorder?.recording == true &&
              !videoRecorder!.busy) {
            unawaited(toggleFileRecording());
          }
          if (!resumed &&
              widget.resumeAt > Duration.zero &&
              (value - widget.resumeAt).abs() < const Duration(seconds: 3)) {
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
        if (mounted) setState(() => duration = value);
        unawaited(verifyResume());
      }),
    );
    subscriptions.add(
      engine.playing.listen((value) {
        if (!value && !starting) liveRecovery?.failed();
        if (mounted) {
          setState(() {
            playing = value;
            if (value) {
              starting = false;
              error = null;
            }
          });
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    revealControls();
    if (source.isLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) liveSurfaceFocus.requestFocus();
      });
    }
    start();
  }

  Future<void> start() async {
    playbackErrorTimer?.cancel();
    playbackProgressVersion++;
    setState(() {
      error = null;
      starting = true;
    });
    try {
      await engine.open(source);
      resumeReady = true;
      if (widget.resumeAt > Duration.zero && !source.isLive) {
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
    HardwareKeyboard.instance.removeHandler(remoteKeys);
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
    if ((widget.resumeAt > Duration.zero && !resumed) ||
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
        widget.episode,
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
    if (widget.nextEpisode != null) await switchEpisode(widget.nextEpisode!);
  }

  Future<void> switchEpisode(Episode selected) async {
    if (advancingEpisode) return;
    setState(() => advancingEpisode = true);
    try {
      await saveProgress();
      skipFinalProgressSave = true;
      progressTimer?.cancel();
      await engine.stop();
      if (mounted) Navigator.of(context).pop(selected);
    } catch (_) {
      if (mounted) {
        setState(() => advancingEpisode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not switch episodes. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> subtitleMenu() async {
    final choice = await showDialog<String>(
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
      await showDialog<void>(
        context: context,
        builder: (_) => OnlineSubtitleDialog(
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

  void revealControls() {
    controlsTimer?.cancel();
    if (!controlsVisible) setState(() => controlsVisible = true);
    if (!fullscreen) return;
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && fullscreen) setState(() => controlsVisible = false);
    });
  }

  String time(Duration value) {
    final seconds = value.inSeconds;
    final minutes = (seconds ~/ 60) % 60;
    final hours = seconds ~/ 3600;
    return '${hours > 0 ? '$hours:' : ''}${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !controlsVisible && !showAutoNext,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        // Capture progress before shutdown events and before the details page resumes.
        progressTimer?.cancel();
        unawaited(saveProgress());
        skipFinalProgressSave = true;
      } else if (showAutoNext) {
        cancelAutoNext();
      } else {
        controlsTimer?.cancel();
        setState(() => controlsVisible = false);
      }
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => togglePlayback(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            togglePlayback(),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () =>
            seek(position + Duration(seconds: seekSeconds)),
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () =>
            seek(position - Duration(seconds: seekSeconds)),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (controlsVisible) {
            controlsTimer?.cancel();
            setState(() => controlsVisible = false);
          } else {
            Navigator.of(context).pop();
          }
        },
      },
      child: Focus(
        focusNode: liveSurfaceFocus,
        canRequestFocus: source.isLive,
        child: Scaffold(
          backgroundColor: const Color(0xff090b13),
          appBar: fullscreen || !controlsVisible
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
                      MouseRegion(
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
                                if (bufferPercent != null)
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
                if (controlsVisible)
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
                                    final mainControls = Wrap(
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
                                            icon: const Icon(Icons.live_tv),
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
                                        if (!source.isLive)
                                          SizedBox(
                                            key: const ValueKey('seek-control'),
                                            width: 84,
                                            height: 36,
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 28,
                                                  child: IconButton(
                                                    padding: EdgeInsets.zero,
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
                                                    tooltip: 'Seek interval',
                                                    enabled:
                                                        !recordingLocksPlayback,
                                                    initialValue: seekSeconds,
                                                    onSelected: (value) {
                                                      if (recordingLocksPlayback) {
                                                        return;
                                                      }
                                                      setState(
                                                        () =>
                                                            seekSeconds = value,
                                                      );
                                                      unawaited(
                                                        savePlaybackPreferences(),
                                                      );
                                                    },
                                                    itemBuilder: (_) => const [
                                                      PopupMenuItem(
                                                        value: 30,
                                                        child: Text(
                                                          '30 seconds',
                                                        ),
                                                      ),
                                                      PopupMenuItem(
                                                        value: 60,
                                                        child: Text('1 minute'),
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
                                                        fit: BoxFit.scaleDown,
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
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
                                                    padding: EdgeInsets.zero,
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
                                              enabled: !recordingLocksPlayback,
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
                                                color: recordingLocksPlayback
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
                                                          WidgetState.focused,
                                                        )
                                                        ? Colors.white
                                                        : Colors.white70,
                                                  ),
                                              overlayColor:
                                                  const WidgetStatePropertyAll(
                                                    Colors.white12,
                                                  ),
                                            ),
                                            tooltip: playing ? 'Pause' : 'Play',
                                            onPressed: togglePlayback,
                                            icon: Icon(
                                              playing
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                            ),
                                          ),
                                        ),
                                        if (engine is VideoDisplayEngine) ...[
                                          IconButton(
                                            tooltip: 'Aspect ratio',
                                            icon: const Icon(
                                              Icons.aspect_ratio,
                                            ),
                                            onPressed: () async {
                                              await showDialog<void>(
                                                context: context,
                                                builder: (_) => VideoDisplayDialog(
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
                                              (liveChannel ?? widget.item) !=
                                                  null)
                                            MyListButton(
                                              key: ValueKey(
                                                (liveChannel ?? widget.item)!
                                                    .id,
                                              ),
                                              provider: widget.provider!,
                                              item:
                                                  (liveChannel ?? widget.item)!,
                                            ),
                                        ],
                                        if (videoRecorder != null)
                                          IconButton(
                                            tooltip: videoRecorder!.recording
                                                ? 'Stop recording'
                                                : 'Record',
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
                                                  : Icons.fiber_manual_record,
                                              color: videoRecorder!.recording
                                                  ? Colors.redAccent
                                                  : null,
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
                                            padding: EdgeInsets.only(left: 12),
                                            child: Text(
                                              '● LIVE',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                    final episodeControls = Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (widget.nextEpisode != null)
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
                                        widget.nextEpisode != null ||
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
                if (showAutoNext && widget.nextEpisode != null)
                  Positioned(
                    right: 20,
                    bottom: controlsVisible ? 170 : 24,
                    child: NextEpisodeCountdown(
                      episode: widget.nextEpisode!,
                      onPlay: () {
                        if (showAutoNext && mounted) {
                          unawaited(playNextEpisode());
                        }
                      },
                      onCancel: cancelAutoNext,
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
