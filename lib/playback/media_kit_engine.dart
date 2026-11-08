import 'playback_diagnostics.dart';
import 'ffmpeg_video_capture.dart';
import 'video_recording_engine.dart';
import 'package:flutter/material.dart';
import 'subtitle_customization.dart';
import 'video_display.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../domain/models.dart';
import 'playback_engine.dart';
import 'frame_preview.dart';

class MediaKitEngine
    implements
        PlaybackEngine,
        DiagnosticPlaybackEngine,
        QualityPlaybackEngine,
        AudioPlaybackEngine,
        AudioTrackPlaybackEngine,
        CompletionPlaybackEngine,
        VideoRecordingEngine,
        BufferingPlaybackEngine,
        FramePreviewEngine,
        SubtitleCustomizationEngine,
        SubtitleOverlayAvoidanceEngine,
        VideoDisplayEngine {
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Stream<bool> get buffering => _player.stream.buffering;
  @override
  Stream<double> get bufferingPercentage => _player.stream.bufferingPercentage;
  final _capture = FfmpegVideoCapture();
  PlaybackSource? _source;
  @override
  Future<void> startVideoRecording(String path) async {
    final source = _source;
    if (source == null) {
      throw StateError('Open a stream before recording.');
    }
    await _capture.start(source, _player.state.position, path);
  }

  @override
  Future<void> stopVideoRecording() => _capture.stop();

  final Player _player;
  final bool multiview;
  MediaKitEngine({
    MPVLogLevel logLevel = MPVLogLevel.error,
    this.multiview = false,
  }) : _player = Player(configuration: PlayerConfiguration(logLevel: logLevel));
  Stream<PlayerLog> get diagnosticLogs => _player.stream.log;
  late final VideoController _controller = VideoController(
    _player,
    configuration: const VideoControllerConfiguration(
      enableHardwareAcceleration: true,
    ),
  );
  final _display = ValueNotifier(const VideoDisplay());
  @override
  VideoDisplay get videoDisplay => _display.value;
  @override
  void setVideoDisplay(VideoDisplay display) => _display.value = display;
  final _subtitleInset = ValueNotifier<double>(0);
  @override
  void setSubtitleBottomInset(double inset) {
    if (!_disposed) _subtitleInset.value = inset;
  }

  final _subtitleStyle = ValueNotifier(const SubtitleAppearance());
  final Map<String, String> _subtitleNames = {};
  @override
  SubtitleAppearance get subtitleAppearance => _subtitleStyle.value;
  @override
  void setSubtitleAppearance(SubtitleAppearance appearance) =>
      _subtitleStyle.value = appearance;
  @override
  Stream<String> get selectedSubtitle => _player.stream.track.map((track) {
    final sub = track.subtitle;
    if (sub.id == 'no') return 'Off';
    if (sub.id == 'auto') return 'Automatic';
    return _subtitleNames[sub.id] ??
        sub.title ??
        sub.language ??
        'Subtitle ${sub.id}';
  });
  @override
  Future<void> addNamedSubtitle(Uri uri, String name) async {
    _subtitleNames[uri.toString()] = name;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(uri.toString(), title: name),
    );
  }

  Player? _preview;
  VideoController? _previewController;
  Future<void>? _previewOpen;
  bool _disposed = false;
  @override
  Future<FramePreview?> previewFrame(
    PlaybackSource source,
    Duration position,
  ) async {
    if (_disposed || source.isLive) return null;
    try {
      _preview ??= Player(
        configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
      );
      _previewController ??= VideoController(_preview!);
      _previewOpen ??= () async {
        await _preview!.setVolume(0);
        await _preview!.open(
          Media(source.uri.toString(), httpHeaders: source.headers),
          play: false,
        );
      }();
      await _previewOpen!.timeout(const Duration(seconds: 8));
      if (_disposed) return null;
      await _preview!.seek(position);
      // A paused decoder needs time to render the frame after seeking.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_disposed) return null;
      final bytes = await _preview!.screenshot().timeout(
        const Duration(seconds: 3),
      );
      final actual = _preview!.state.position;
      if (bytes == null ||
          (actual - position).abs() > const Duration(seconds: 3)) {
        return null;
      }
      return FramePreview(bytes, actual);
    } catch (_) {
      return null; // Some providers do not support seeking or a second stream.
    }
  }

  @override
  Stream<Duration> get position => _player.stream.position;
  @override
  Stream<Duration> get duration => _player.stream.duration;
  @override
  Stream<bool> get playing => _player.stream.playing;
  @override
  Stream<String> get errors =>
      _player.stream.error.map((raw) => PlaybackFailure.from(raw).message);
  @override
  Stream<List<SubtitleOption>> get subtitles => _player.stream.tracks.map(
    (tracks) => tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .map(
          (track) => SubtitleOption(
            track.id,
            [track.title, track.language]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' - ')
                    .isEmpty
                ? '${track.codec == 'eia_608' ? 'CC' : 'Subtitle'} ${track.id}'
                : [
                    track.title,
                    track.language,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' - '),
            language: track.language,
            codec: track.codec,
          ),
        )
        .toList(),
  );
  bool? _videoPtsSupported;
  @override
  Future<PlaybackDiagnostics> readDiagnostics() async {
    final state = _player.state;
    final videos = state.tracks.video.where(
      (t) =>
          t.id != 'auto' &&
          t.id != 'no' &&
          t.image != true &&
          t.albumart != true,
    );
    final video =
        videos.where((t) => t.id == state.track.video.id).firstOrNull ??
        videos.firstOrNull;
    final audio = state.tracks.audio
        .where((t) => t.id == state.track.audio.id)
        .firstOrNull;
    double? buffer, pts;
    final native = _player.platform;
    if (!_disposed && native is NativePlayer) {
      try {
        buffer = double.tryParse(
          await native.getProperty('demuxer-cache-duration'),
        );
      } catch (_) {}
      if (_videoPtsSupported != false && video != null) {
        try {
          pts = double.tryParse(await native.getProperty('video-pts'));
          if (pts != null) _videoPtsSupported = true;
        } catch (_) {
          _videoPtsSupported = false;
        }
      }
    }
    return PlaybackDiagnostics(
      videoCodec: video?.codec,
      audioCodec: audio?.codec,
      decoder: video?.decoder,
      width: state.width ?? video?.w,
      height: state.height ?? video?.h,
      fps: video?.fps,
      bufferSeconds: buffer,
      buffering: state.buffering,
      videoPosition: pts != null && pts.isFinite && pts >= 0
          ? Duration(milliseconds: (pts * 1000).round())
          : null,
    );
  }

  @override
  List<PlaybackQuality> get videoQualities {
    final tracks = _player.state.tracks.video
        .where(
          (t) =>
              t.id != 'auto' &&
              t.id != 'no' &&
              t.image != true &&
              t.albumart != true,
        )
        .toList();
    if (tracks.length < 2 ||
        (tracks.map((t) => t.h).whereType<int>().toSet().length < 2 &&
            tracks.map((t) => t.bitrate).whereType<int>().toSet().length < 2)) {
      return [];
    }
    return tracks
        .map(
          (t) => PlaybackQuality(
            t.id,
            '${t.h == null ? 'Video track ${t.id}' : '${t.h}p'}${t.bitrate == null ? '' : ' - ${(t.bitrate! / 1000).round()} kbps'}',
            height: t.h,
            bitrate: t.bitrate,
          ),
        )
        .toList();
  }

  @override
  String get selectedVideoQuality => _player.state.track.video.id;
  @override
  Future<void> selectVideoQuality(String id) => _player.setVideoTrack(
    _player.state.tracks.video.firstWhere(
      (t) => t.id == id && t.id != 'no' && t.id != 'auto',
    ),
  );

  @override
  Future<void> selectSubtitle(String id) async {
    final track = id == 'no'
        ? SubtitleTrack.no()
        : id == 'auto'
        ? SubtitleTrack.auto()
        : _player.state.tracks.subtitle.firstWhere((track) => track.id == id);
    await _player.setSubtitleTrack(track);
    // media_kit updates its Dart track state even when mpv rejects a decoder.
    // Verify the native selection rather than reporting CC as enabled falsely.
    final captionCodec = track.codec == 'eia_608' || track.codec == 'cea_708';
    final native = _player.platform;
    if (_source?.isLive == true &&
        id != 'no' &&
        (captionCodec || id == 'auto') &&
        native is NativePlayer) {
      String? actual;
      try {
        actual = await native.getProperty('sid');
      } catch (_) {
        /* Optional on some engines. */
      }
      if (actual == 'no') {
        throw const ProviderException(
          "The player could not start this channel's closed-caption decoder.",
        );
      }
    }
  }

  @override
  List<SubtitleOption> get currentAudioTracks => _player.state.tracks.audio
      .where((track) => track.id != 'no' && track.id != 'auto')
      .map(
        (track) => SubtitleOption(
          track.id,
          [track.title, track.language]
                  .whereType<String>()
                  .where((value) => value.isNotEmpty)
                  .join(' ? ')
                  .isEmpty
              ? 'Audio ${track.id}'
              : [track.title, track.language]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join(' ? '),
        ),
      )
      .toList();
  @override
  Stream<List<SubtitleOption>> get audioTracks =>
      _player.stream.tracks.map((_) => currentAudioTracks);
  @override
  String get selectedAudioTrack => _player.state.track.audio.id;
  @override
  Future<void> selectAudioTrack(String id) => _player.setAudioTrack(
    id == 'auto'
        ? AudioTrack.auto()
        : _player.state.tracks.audio.firstWhere((track) => track.id == id),
  );
  @override
  Future<void> addSubtitle(Uri uri) =>
      _player.setSubtitleTrack(SubtitleTrack.uri(uri.toString()));
  @override
  Future<void> open(PlaybackSource source) async {
    await _capture.stop();
    _source = source;
    final native = _player.platform;
    if (native is NativePlayer && source.isLive) {
      // Keep live jitter buffering bounded for Fire TV memory and live latency.
      final properties = <String, String>{
        'cache': 'yes',
        'cache-secs': multiview ? '6' : '15',
        'cache-pause-wait': '3',
        'network-timeout': '15',
        'demuxer-max-bytes': '${(multiview ? 8 : 32) * 1024 * 1024}',
        'demuxer-max-back-bytes': '${(multiview ? 2 : 8) * 1024 * 1024}',
      };
      for (final property in properties.entries) {
        try {
          await native.setProperty(property.key, property.value);
        } catch (_) {
          /* Unsupported options must not prevent playback. */
        }
      }
    }
    await _player.open(
      Media(source.uri.toString(), httpHeaders: source.headers),
    );
  }

  @override
  Future<void> togglePause() => _player.playOrPause();
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setRate(double rate) => _player.setRate(rate);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() async {
    _disposed = true;
    await _capture.stop();
    await _preview?.dispose();
    await _player.dispose();
    _subtitleInset.dispose();
    _subtitleStyle.dispose();
    _display.dispose();
  }

  @override
  Widget surface() => ValueListenableBuilder<SubtitleAppearance>(
    valueListenable: _subtitleStyle,
    builder: (_, appearance, _) => Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<VideoDisplay>(
          valueListenable: _display,
          builder: (_, display, _) => ClipRect(
            child: FractionalTranslation(
              translation: display.pan,
              child: Transform.scale(
                scale: display.zoom,
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: display.fit,
                  aspectRatio: display.aspectRatio,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                ),
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: StreamBuilder<List<String>>(
            stream: _player.stream.subtitle,
            initialData: _player.state.subtitle,
            builder: (_, snapshot) => ValueListenableBuilder<double>(
              valueListenable: _subtitleInset,
              builder: (_, inset, _) => Align(
                alignment: appearance.alignment,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + (appearance.position == 'Bottom' ? inset : 0),
                  ),
                  child: Text(
                    (snapshot.data ?? [])
                        .where((line) => line.trim().isNotEmpty)
                        .join('\n'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: appearance.size,
                      color: SubtitleAppearance.colors[appearance.color],
                      backgroundColor: Colors.black54,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
