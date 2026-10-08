import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../domain/models.dart';
import 'playback_engine.dart';

class MediaKitEngine implements PlaybackEngine {
  final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error),
  );
  late final VideoController _controller = VideoController(_player);
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
  Future<void> open(PlaybackSource source) =>
      _player.open(Media(source.uri.toString(), httpHeaders: source.headers));
  @override
  Future<void> togglePause() => _player.playOrPause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
  @override
  Widget surface() => Video(controller: _controller, controls: NoVideoControls);
}
