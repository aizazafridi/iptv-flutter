import 'package:flutter/widgets.dart';
import '../domain/models.dart';

/// Changing the video library never requires changes to provider integrations.
abstract interface class PlaybackEngine {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<String> get errors;
  Future<void> open(PlaybackSource source);
  Future<void> togglePause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
  Widget surface();
}
