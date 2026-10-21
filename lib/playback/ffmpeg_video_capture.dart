import 'dart:async';
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffprobe_kit.dart';
import '../domain/models.dart';

/// Copies compressed media into a local file without re-encoding video.
/// This uses a separate HTTP connection; the provider must allow it.
class FfmpegVideoCapture {
  FFmpegSession? _session;
  Completer<void>? _finished;
  String? _path;

  Future<void> start(
    PlaybackSource source,
    Duration position,
    String path,
  ) async {
    if (_session != null) throw StateError('Recording is already active.');
    // Provider URLs contain credentials. Never forward native FFmpeg logs.
    await FFmpegKitConfig.disableLogs();
    final finished = Completer<void>();
    _finished = finished;
    _path = path;
    final headers = source.headers.entries.map((entry) {
      if (entry.key.contains(RegExp(r'[\r\n]')) ||
          entry.value.contains(RegExp(r'[\r\n]'))) {
        throw ArgumentError('Invalid stream header.');
      }
      return '${entry.key}: ${entry.value}\r\n';
    }).join();
    _session = await FFmpegKit.executeWithArgumentsAsync(
      [
        '-hide_banner',
        '-loglevel',
        'quiet',
        '-nostdin',
        '-y',
        if (!source.isLive) ...[
          '-re',
          '-ss',
          (position.inMilliseconds / 1000).toStringAsFixed(3),
        ],
        if (source.isLive && ['http', 'https'].contains(source.uri.scheme)) ...[
          '-rw_timeout',
          '10000000',
        ],
        if (headers.isNotEmpty) ...['-headers', headers],
        '-i',
        source.uri.toString(),
        '-map',
        '0:v?',
        '-map',
        '0:a?',
        '-c',
        'copy',
        '-avoid_negative_ts',
        'make_zero',
        '-flush_packets',
        '1',
        '-f',
        'matroska',
        path,
      ],
      (_) {
        if (!finished.isCompleted) finished.complete();
      },
    );
    try {
      for (var attempt = 0; attempt < 150; attempt++) {
        final file = File(path);
        if (await file.exists() && await file.length() > 0) return;
        if (finished.isCompleted) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('The provider could not start this recording.');
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final session = _session;
    if (session == null) return;
    // Cancellation sends a native interrupt, allowing the muxer to finalize.
    await FFmpegKit.cancel(session.getSessionId());
    await _finished!.future.timeout(const Duration(seconds: 15));
    _session = null;
    _finished = null;
    final path = _path!;
    _path = null;
    final probe = await FFprobeKit.getMediaInformation(path);
    final duration =
        double.tryParse(probe.getMediaInformation()?.getDuration() ?? '') ?? 0;
    if (duration <= 0) {
      throw StateError('The recording contains no playable media.');
    }
  }
}
