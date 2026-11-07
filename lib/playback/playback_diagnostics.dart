/// Only allowlisted categories cross into the UI. Never expose URLs or tokens.
class PlaybackFailure {
  final String message;
  final bool retryable;
  const PlaybackFailure(this.message, {this.retryable = true});
  factory PlaybackFailure.from(String raw) {
    final text = raw.toLowerCase();
    final http = RegExp(
      r'(?:http(?:/[\d.]+)?(?: error| status(?: code)?)?[:\s]+|server returned\s+)([45]\d{2})\b',
    ).firstMatch(text);
    final code = http?.group(1);
    if (code != null) {
      return PlaybackFailure(
        'HTTP $code: ${code == '401' || code == '403'
            ? 'access denied'
            : code == '404'
            ? 'stream unavailable'
            : 'connection failed'}.',
        retryable: !['401', '403', '404', '410'].contains(code),
      );
    }
    if (text.contains('codec') || text.contains('decoder')) {
      return const PlaybackFailure(
        'Video/audio decoding failed or the codec is unsupported.',
        retryable: false,
      );
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return const PlaybackFailure('Connection timed out.');
    }
    if (text.contains('resolve') || text.contains('dns')) {
      return const PlaybackFailure('Could not resolve the streaming server.');
    }
    if (text.contains('secure connection failed') ||
        text.contains('certificate') ||
        text.contains('tls') ||
        text.contains('ssl')) {
      return const PlaybackFailure(
        'Secure connection failed.',
        retryable: false,
      );
    }
    if (text.contains('refused')) {
      return const PlaybackFailure(
        'The streaming server refused the connection.',
      );
    }
    return const PlaybackFailure('Playback connection failed.');
  }
}

class PlaybackQuality {
  final String id, label;
  final int? height, bitrate;
  const PlaybackQuality(this.id, this.label, {this.height, this.bitrate});
}

class PlaybackDiagnostics {
  final String? videoCodec, audioCodec, decoder;
  final int? width, height;
  final double? fps, bufferSeconds;
  final Duration? videoPosition;
  final bool buffering;
  const PlaybackDiagnostics({
    this.videoCodec,
    this.audioCodec,
    this.decoder,
    this.width,
    this.height,
    this.fps,
    this.bufferSeconds,
    this.videoPosition,
    this.buffering = false,
  });
}

abstract interface class DiagnosticPlaybackEngine {
  Future<PlaybackDiagnostics> readDiagnostics();
}

abstract interface class QualityPlaybackEngine {
  List<PlaybackQuality> get videoQualities;
  String get selectedVideoQuality;
  Future<void> selectVideoQuality(String id);
}
