import 'package:flutter/widgets.dart';
import '../domain/models.dart';

/// Changing the video library never requires changes to provider integrations.
abstract interface class PlaybackEngine {
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<bool> get playing;
  Stream<String> get errors;
  Stream<List<SubtitleOption>> get subtitles;
  Future<void> selectSubtitle(String id);
  Future<void> addSubtitle(Uri uri);
  Future<void> open(PlaybackSource source);
  Future<void> togglePause();
  Future<void> seek(Duration position);
  Future<void> setRate(double rate);
  Future<void> stop();
  Future<void> dispose();
  Widget surface();
}

/// Optional playback-buffer progress; independent of the complete file size.
abstract interface class BufferingPlaybackEngine {
  Stream<bool> get buffering;
  Stream<double> get bufferingPercentage;
}

/// End-of-media notification, separate from pausing or buffering.
abstract interface class CompletionPlaybackEngine {
  Stream<bool> get completed;
}

/// Optional audio routing for independent simultaneous players.
abstract interface class AudioPlaybackEngine {
  Future<void> setVolume(double volume);
}
