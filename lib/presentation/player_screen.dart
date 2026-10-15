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
import '../data/recorded_segments.dart';
import 'recordings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../playback/playback_engine.dart';
import '../playback/media_kit_engine.dart';

class PlayerScreen extends StatefulWidget {
  final PlaybackSource source;
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
  RecordedSegments? segments;
  bool segmentsDisposed = false, loopSeekPending = false;
  Completer<bool>? loopSeekConfirmation;
  int loopSeekVersion = 0;
  void cancelLoopSeek() {
    loopSeekVersion++;
    final pending = loopSeekConfirmation;
    loopSeekConfirmation = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    loopSeekPending = false;
  }

  Duration? recordingReturnPosition;
  bool restoringRecording = false;
  Duration get timelineStart => segments?.activeLoop?.start ?? Duration.zero;
  Duration get timelineEnd => segments?.activeLoop?.end ?? duration;
  void segmentsChanged() {
    if (mounted) {
      setState(() {});
      if (segments?.activeLoop == null &&
          recordingReturnPosition != null &&
          !restoringRecording) {
        unawaited(stopRecordingPlayback());
      }
    }
  }

  Future<void> stopRecordingPlayback() async {
    final target = recordingReturnPosition;
    recordingReturnPosition = null;
    restoringRecording = true;
    cancelLoopSeek();
    segments?.loop(null);
    if (mounted) setState(() => dragPosition = null);
    try {
      if (target != null) {
        await engine.seek(target);
        if (mounted) setState(() => position = target);
      }
    } catch (_) {
      recordingMessage(
        'Could not return to the original position. Please retry.',
      );
    } finally {
      restoringRecording = false;
    }
  }

  void recordingMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
    }
  }

  Future<void> loadSegments() async {
    final history = widget.history, item = widget.item;
    if (source.isLive || history == null || item == null) return;
    final store = RecordedSegments(
      history.scope,
      '${item.type.name}:${item.id}:${widget.episode?.id ?? ""}',
    );
    segments = store;
    try {
      await store.load();
    } catch (_) {
      recordingMessage(
        'Could not load recordings. Please retry by reopening this player.',
      );
    }
    if (segmentsDisposed) return;
    store.addListener(segmentsChanged);
    if (mounted) setState(() {});
  }

  Future<void> toggleRecording() async {
    final store = segments;
    if (store == null || !store.loaded || store.saving) return;
    if (store.recordingStart == null) {
      loopSeekPending = false;
      if (store.activeLoop != null) await stopRecordingPlayback();
      store.begin(position);
    } else {
      if (position <= store.recordingStart!) {
        recordingMessage(
          'Play beyond the start position before stopping the recording.',
        );
        return;
      }
      try {
        await store.finish(position);
        recordingMessage('Recording saved.');
      } catch (_) {
        recordingMessage('Could not save recording. Please retry.');
      }
    }
  }

  Future<void> showRecordings() async {
    final store = segments;
    if (store == null) return;
    final returnPosition = recordingReturnPosition ?? position;
    final selected = await showDialog<RecordedSegment>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => RecordingsPanel(
        segments: store,
        title: source.title,
        onStop: stopRecordingPlayback,
      ),
    );
    if (!mounted || selected == null) return;
    if (duration > Duration.zero && selected.end > duration) {
      recordingMessage('This recording is outside the current media duration.');
      return;
    }
    if (store.recordingStart != null) {
      recordingMessage('Stop recording before playing a saved segment.');
      return;
    }
    recordingReturnPosition = returnPosition;
    setState(() {
      dragPosition = null;
      resumed = true;
    });
    store.loop(selected);
    cancelLoopSeek();
    final reached = await seekLoopStart(selected);
    if (mounted && reached && !playing) await engine.togglePause();
  }

  Future<bool> seekLoopStart(RecordedSegment segment) async {
    if (loopSeekPending) return false;
    loopSeekPending = true;
    final version = ++loopSeekVersion;
    try {
      // seek() acknowledges the command, not that playback reached the target.
      // Some network streams first report zero or ignore the initial command.
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!mounted ||
            version != loopSeekVersion ||
            segments?.activeLoop != segment) {
          return false;
        }
        final confirmation = Completer<bool>();
        loopSeekConfirmation = confirmation;
        await engine.seek(segment.start).timeout(const Duration(seconds: 5));
        final reached = await confirmation.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => false,
        );
        if (!mounted || version != loopSeekVersion) return false;
        if (reached) return true;
      }
      throw StateError('Recording seek was not confirmed');
    } catch (_) {
      if (mounted && version == loopSeekVersion) {
        await stopRecordingPlayback();
        recordingMessage(
          'Could not seek to this recording. This stream may not support seeking.',
        );
      }
      return false;
    } finally {
      if (version == loopSeekVersion) {
        loopSeekConfirmation = null;
        loopSeekPending = false;
      }
    }
  }

  void checkRecordingLoop(Duration value) {
    final loop = segments?.activeLoop;
    if (loop == null) return;
    final confirmation = loopSeekConfirmation;
    if (value >= loop.start && value < loop.end) {
      if (confirmation != null &&
          !confirmation.isCompleted &&
          value - loop.start <= const Duration(seconds: 2)) {
        confirmation.complete(true);
      }
      return;
    }
    if (!loopSeekPending) unawaited(seekLoopStart(loop));
  }

  PlaybackSource? liveSource;
  PlaybackSource get source => liveSource ?? widget.source;
  ContentItem? liveChannel;
  bool switchingChannel = false;
  Future<void> chooseChannel() async {
    final selected = await showDialog<ContentItem>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => ChannelPicker(
        title: widget.channelCategory,
        load: widget.loadChannels!,
        currentId: (liveChannel ?? widget.item)?.id,
      ),
    );
    if (!mounted ||
        selected == null ||
        selected.id == (liveChannel ?? widget.item)?.id) {
      return;
    }
    setState(() => switchingChannel = true);
    try {
      final next = await widget.resolveChannel!(selected);
      if (!mounted) return;
      setState(() {
        liveSource = next;
        liveChannel = selected;
        error = null;
        starting = true;
      });
      await engine.open(next);
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not play this channel. Please retry.';
          starting = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => switchingChannel = false);
        revealControls();
      }
    }
  }

  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false, fullscreen = false, starting = true;
  double? dragPosition;
  bool controlsVisible = true;
  Timer? controlsTimer;
  Timer? progressTimer;
  bool resumed = false;
  bool advancingEpisode = false;
  int seekSeconds = 30;
  double playbackRate = 1;
  Future<void> setPlaybackRate(double rate) async {
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
      (engine as VideoDisplayEngine).setVideoDisplay(
        VideoDisplay(
          ratio: VideoDisplay.ratios.contains(saved['ratio'])
              ? saved['ratio']
              : 'Original',
          zoom: ((saved['zoom'] as num?)?.toDouble() ?? 1).clamp(0.5, 3),
          pan: Offset(
            ((saved['panX'] as num?)?.toDouble() ?? 0).clamp(-0.5, 0.5),
            ((saved['panY'] as num?)?.toDouble() ?? 0).clamp(-0.5, 0.5),
          ),
        ),
      );
    }
    await engine.setRate(playbackRate);
    if (mounted) setState(() {});
  }

  String get seekLabel => seekSeconds == 30
      ? '30 seconds'
      : '${seekSeconds ~/ 60} ${seekSeconds == 60 ? 'minute' : 'minutes'}';
  Future<void> chooseEpisode() async {
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
    previewDebounce = Timer(const Duration(milliseconds: 180), fetchPreview);
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
    unawaited(loadSegments());
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
          setState(() => position = value);
          checkRecordingLoop(value);
        }
      }),
    );
    subscriptions.add(
      engine.duration.listen((value) {
        if (mounted) setState(() => duration = value);
        if (!resumed &&
            segments?.activeLoop == null &&
            value > Duration.zero &&
            widget.resumeAt > Duration.zero) {
          resumed = true;
          unawaited(seek(widget.resumeAt));
        }
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
    start();
  }

  Future<void> start() async {
    setState(() {
      error = null;
      starting = true;
    });
    try {
      await engine.open(source);
      if (mounted) await restorePlaybackPreferences();
      if (mounted && !source.isLive) await restoreSubtitles();
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
    segmentsDisposed = true;
    cancelLoopSeek();
    final store = segments;
    if (store != null) {
      store.removeListener(segmentsChanged);
      store.dispose();
    }
    controlsTimer?.cancel();
    progressTimer?.cancel();
    previewDebounce?.cancel();
    previewHide?.cancel();
    previewVersion++;
    unawaited(saveProgress());
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(engine.dispose());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  Future<void> saveProgress() async {
    if (skipFinalProgressSave ||
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
        recordingReturnPosition ?? position,
        duration,
        DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> seek(Duration target) async {
    if (source.isLive || duration <= Duration.zero) return;
    final milliseconds = target.inMilliseconds.clamp(
      timelineStart.inMilliseconds,
      timelineEnd.inMilliseconds - 1,
    );
    requestPreview(Duration(milliseconds: milliseconds));
    await engine.seek(Duration(milliseconds: milliseconds));
  }

  Future<void> playNextEpisode() async {
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
    if (!fullscreen) return;
    controlsTimer?.cancel();
    if (!controlsVisible) setState(() => controlsVisible = true);
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
    canPop: !fullscreen,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        // Capture progress before shutdown events and before the details page resumes.
        progressTimer?.cancel();
        unawaited(saveProgress());
        skipFinalProgressSave = true;
      } else {
        toggleFullscreen();
      }
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.select): revealControls,
        const SingleActivator(LogicalKeyboardKey.enter): revealControls,
        const SingleActivator(LogicalKeyboardKey.arrowUp): revealControls,
        const SingleActivator(LogicalKeyboardKey.arrowDown): revealControls,
        const SingleActivator(LogicalKeyboardKey.space): () =>
            engine.togglePause(),
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
            engine.togglePause(),
        const SingleActivator(LogicalKeyboardKey.mediaFastForward): () =>
            seek(position + Duration(seconds: seekSeconds)),
        const SingleActivator(LogicalKeyboardKey.mediaRewind): () =>
            seek(position - Duration(seconds: seekSeconds)),
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
                  source.title,
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
                    MouseRegion(
                      onHover: (_) => revealControls(),
                      cursor: fullscreen && !controlsVisible
                          ? SystemMouseCursors.none
                          : MouseCursor.defer,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: revealControls,
                        child: engine.surface(),
                      ),
                    ),
                    if (previewTarget != null)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
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
                                    framePreview?.position ?? previewTarget!,
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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
              if (!fullscreen || controlsVisible)
                Container(
                  color: const Color(0xff15192a),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      if (!source.isLive)
                        Row(
                          children: [
                            Text(
                              segments?.activeLoop != null
                                  ? time(timelineStart)
                                  : time(
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
                                min: timelineStart.inMilliseconds.toDouble(),
                                max: timelineEnd.inMilliseconds > 0
                                    ? timelineEnd.inMilliseconds.toDouble()
                                    : 1,
                                value:
                                    (dragPosition ??
                                            position.inMilliseconds.toDouble())
                                        .clamp(
                                          timelineStart.inMilliseconds
                                              .toDouble(),
                                          timelineEnd.inMilliseconds > 0
                                              ? timelineEnd.inMilliseconds
                                                    .toDouble()
                                              : 1,
                                        ),
                                onChangeStart: duration <= Duration.zero
                                    ? null
                                    : (value) {
                                        setState(() => dragPosition = value);
                                        requestPreview(
                                          Duration(milliseconds: value.toInt()),
                                        );
                                      },
                                onChanged: duration <= Duration.zero
                                    ? null
                                    : (value) {
                                        setState(() => dragPosition = value);
                                        requestPreview(
                                          Duration(milliseconds: value.toInt()),
                                        );
                                      },
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
                            Text(time(timelineEnd)),
                          ],
                        ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final mainControls = Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (!source.isLive)
                                SizedBox(
                                  key: const ValueKey('seek-control'),
                                  width: 96,
                                  height: 48,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 32,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 48,
                                          ),
                                          tooltip: 'Rewind $seekLabel',
                                          icon: const Icon(
                                            Icons.fast_rewind,
                                            size: 22,
                                          ),
                                          onPressed: () => seek(
                                            position -
                                                Duration(seconds: seekSeconds),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 32,
                                        height: 48,
                                        child: PopupMenuButton<int>(
                                          tooltip: 'Seek interval',
                                          initialValue: seekSeconds,
                                          onSelected: (value) {
                                            setState(() => seekSeconds = value);
                                            unawaited(
                                              savePlaybackPreferences(),
                                            );
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 30,
                                              child: Text('30 seconds'),
                                            ),
                                            PopupMenuItem(
                                              value: 60,
                                              child: Text('1 minute'),
                                            ),
                                            PopupMenuItem(
                                              value: 120,
                                              child: Text('2 minutes'),
                                            ),
                                            PopupMenuItem(
                                              value: 180,
                                              child: Text('3 minutes'),
                                            ),
                                          ],
                                          child: Center(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.timer_outlined,
                                                    size: 20,
                                                  ),
                                                  const Icon(
                                                    Icons.arrow_drop_down,
                                                    size: 16,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 32,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 48,
                                          ),
                                          tooltip: 'Forward $seekLabel',
                                          icon: const Icon(
                                            Icons.fast_forward,
                                            size: 22,
                                          ),
                                          onPressed: () => seek(
                                            position +
                                                Duration(seconds: seekSeconds),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!source.isLive)
                                SizedBox(
                                  key: const ValueKey('speed-control'),
                                  width: 48,
                                  height: 48,
                                  child: PopupMenuButton<double>(
                                    tooltip: 'Playback speed',
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
                                    child: const Icon(Icons.speed),
                                  ),
                                ),
                              SizedBox(
                                key: const ValueKey('play-pause-control'),
                                width: 48,
                                height: 48,
                                child: IconButton(
                                  autofocus: true,
                                  tooltip: playing ? 'Pause' : 'Play',
                                  onPressed: engine.togglePause,
                                  icon: Icon(
                                    playing ? Icons.pause : Icons.play_arrow,
                                  ),
                                ),
                              ),
                              if (engine is VideoDisplayEngine) ...[
                                IconButton(
                                  tooltip: 'Aspect ratio',
                                  icon: const Icon(Icons.aspect_ratio),
                                  onPressed: () async {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (_) => VideoDisplayDialog(
                                        engine: engine as VideoDisplayEngine,
                                      ),
                                    );
                                    await savePlaybackPreferences();
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Zoom',
                                  icon: const Icon(Icons.zoom_in),
                                  onPressed: () async {
                                    await showDialog<void>(
                                      context: context,
                                      builder: (_) => VideoDisplayDialog(
                                        engine: engine as VideoDisplayEngine,
                                        zoom: true,
                                      ),
                                    );
                                    await savePlaybackPreferences();
                                  },
                                ),
                              ],
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
                                  icon: const Icon(Icons.view_list_outlined),
                                  onPressed: showEpg,
                                ),
                              if (!source.isLive && segments != null)
                                IconButton(
                                  tooltip: segments!.recordingStart == null
                                      ? 'Record'
                                      : 'Stop recording',
                                  onPressed:
                                      segments!.loaded &&
                                          !segments!.saving &&
                                          !starting
                                      ? toggleRecording
                                      : null,
                                  icon: Icon(
                                    segments!.recordingStart == null
                                        ? Icons.fiber_manual_record
                                        : Icons.stop_circle,
                                    color: segments!.recordingStart == null
                                        ? null
                                        : Colors.redAccent,
                                  ),
                                ),
                              if (!source.isLive)
                                IconButton(
                                  tooltip: 'Subtitles',
                                  onPressed: subtitleMenu,
                                  icon: const Icon(Icons.subtitles_outlined),
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
                                    style: TextStyle(color: Colors.redAccent),
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
                                if (!source.isLive && segments != null) ...[
                                  if (segments!.activeLoop != null)
                                    IconButton(
                                      tooltip: 'Stop recording playback',
                                      onPressed: stopRecordingPlayback,
                                      icon: const Icon(Icons.repeat_on),
                                    ),
                                  IconButton(
                                    tooltip: 'Recordings',
                                    onPressed:
                                        segments!.loaded && !segments!.saving
                                        ? showRecordings
                                        : null,
                                    icon: const Icon(
                                      Icons.video_library_outlined,
                                    ),
                                  ),
                                ],
                                if (widget.episodes.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Episodes',
                                    icon: const Icon(Icons.playlist_play),
                                    onPressed: advancingEpisode
                                        ? null
                                        : chooseEpisode,
                                  ),
                              ],
                            ),
                          );
                          final hasRightControls =
                              widget.nextEpisode != null ||
                              widget.episodes.isNotEmpty ||
                              (!source.isLive && segments != null);
                          if (constraints.maxWidth < 650 && hasRightControls) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
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
