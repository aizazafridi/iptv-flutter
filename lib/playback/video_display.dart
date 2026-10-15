import 'package:flutter/material.dart';

class VideoDisplay {
  final String ratio;
  final double zoom;
  final Offset pan;
  const VideoDisplay({
    this.ratio = 'Original',
    this.zoom = 1,
    this.pan = Offset.zero,
  });
  static const ratios = ['Original', '16:9', '4:3', '21:9', 'Stretch', 'Fill'];
  double? get aspectRatio => switch (ratio) {
    '16:9' => 16 / 9,
    '4:3' => 4 / 3,
    '21:9' => 21 / 9,
    _ => null,
  };
  BoxFit get fit => switch (ratio) {
    'Stretch' => BoxFit.fill,
    'Fill' => BoxFit.cover,
    _ => BoxFit.contain,
  };
}

abstract interface class VideoDisplayEngine {
  VideoDisplay get videoDisplay;
  void setVideoDisplay(VideoDisplay display);
}
