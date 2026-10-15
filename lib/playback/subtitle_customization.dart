import 'package:flutter/material.dart';

class SubtitleAppearance {
  final double size;
  final String color, position;
  const SubtitleAppearance({
    this.size = 24,
    this.color = 'White',
    this.position = 'Bottom',
  });
  static const colors = <String, Color>{
    'White': Colors.white,
    'Yellow': Colors.yellow,
    'Cyan': Colors.cyanAccent,
    'Green': Colors.lightGreenAccent,
  };
  Alignment get alignment => switch (position) {
    'Top' => Alignment.topCenter,
    'Middle' => Alignment.center,
    _ => Alignment.bottomCenter,
  };
}

abstract interface class SubtitleCustomizationEngine {
  Stream<String> get selectedSubtitle;
  SubtitleAppearance get subtitleAppearance;
  void setSubtitleAppearance(SubtitleAppearance appearance);
  Future<void> addNamedSubtitle(Uri uri, String name);
}
