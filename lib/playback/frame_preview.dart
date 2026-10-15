import 'dart:typed_data';
import '../domain/models.dart';

class FramePreview {
  final Uint8List image;
  final Duration position;
  const FramePreview(this.image, this.position);
}

abstract interface class FramePreviewEngine {
  Future<FramePreview?> previewFrame(PlaybackSource source, Duration position);
}
