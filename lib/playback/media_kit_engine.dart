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
        AudioPlaybackEngine,
        CompletionPlaybackEngine,
        VideoRecordingEngine,
        BufferingPlaybackEngine,
        FramePreviewEngine,
        SubtitleCustomizationEngine,
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
  MediaKitEngine({MPVLogLevel logLevel = MPVLogLevel.error})
    : _player = Player(configuration: PlayerConfiguration(logLevel: logLevel));
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
  Stream<String> get errors => _player.stream.error.map(
    (_) => 'Playback failed. Check your connection and content availability.',
  );
  @override
  Stream<List<SubtitleOption>> get subtitles => _player.stream.tracks.map(
    (tracks) => tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .map(
          (track) => SubtitleOption(
            track.id,
            [track.title, track.language]
                    .whereType<String>()
                    .where((text) => text.isNotEmpty)
                    .join(' · ')
                    .isEmpty
                ? 'Subtitle ${track.id}'
                : [track.title, track.language]
                      .whereType<String>()
                      .where((text) => text.isNotEmpty)
                      .join(' · '),
          ),
        )
        .toList(),
  );
  @override
  Future<void> selectSubtitle(String id) => _player.setSubtitleTrack(
    id == 'no'
        ? SubtitleTrack.no()
        : id == 'auto'
        ? SubtitleTrack.auto()
        : _player.state.tracks.subtitle.firstWhere((track) => track.id == id),
  );
  @override
  Future<void> addSubtitle(Uri uri) =>
      _player.setSubtitleTrack(SubtitleTrack.uri(uri.toString()));
  @override
  Future<void> open(PlaybackSource source) async {
    await _capture.stop();
    _source = source;
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
            builder: (_, snapshot) => Align(
              alignment: appearance.alignment,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  (snapshot.data ?? [])
                      .where((line) => line.trim().isNotEmpty)
                      .join('\n'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: appearance.size,
                    color: SubtitleAppearance.colors[appearance.color],
                    backgroundColor: Colors.black54,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
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
