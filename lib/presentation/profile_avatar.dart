import 'package:flutter/material.dart';
import '../domain/models.dart';

/// Offline portraits with stable indices for saved account selections.
class ProfileAvatar extends StatelessWidget {
  final int index;
  final double size;
  const ProfileAvatar(this.index, {super.key, this.size = 72});
  static const names = [
    'Cinema portrait 1',
    'Cinema portrait 2',
    'Cinema portrait 3',
    'Cinema portrait 4',
    'Cinema portrait 5',
    'Cinema portrait 6',
    'Cinema portrait 7',
    'Cinema portrait 8',
  ];
  // Square, face-focused source rectangles. Original photographs stay intact.
  // Each crop is rendered at the same requested size and clipped by ClipOval.
  static const _photos = [
    (width: 1408.0, height: 768.0, x: 525.0, y: 10.0, side: 650.0),
    (width: 928.0, height: 1152.0, x: 250.0, y: 80.0, side: 460.0),
    (width: 1408.0, height: 768.0, x: 470.0, y: 0.0, side: 660.0),
    (width: 1408.0, height: 768.0, x: 405.0, y: 0.0, side: 670.0),
    (width: 1376.0, height: 768.0, x: 365.0, y: 0.0, side: 650.0),
    (width: 1408.0, height: 768.0, x: 375.0, y: 0.0, side: 650.0),
    (width: 1408.0, height: 768.0, x: 425.0, y: 0.0, side: 670.0),
    (width: 1376.0, height: 768.0, x: 400.0, y: 0.0, side: 640.0),
  ];

  Widget photo(int selected) {
    final index = selected;
    final crop = _photos[index];
    final scale = size / crop.side;
    return Semantics(
      label: names[selected],
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Stack(
            children: [
              Positioned(
                left: -crop.x * scale,
                top: -crop.y * scale,
                width: crop.width * scale,
                height: crop.height * scale,
                child: Image.asset(
                  'assets/avatars/photos/portrait_${(index + 1).toString().padLeft(2, '0')}.jpeg',
                  fit: BoxFit.fill,
                  cacheWidth: 512,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Colors.indigo,
                    child: Center(
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(names.length == profileAvatarCount);
    final selected = index.clamp(0, names.length - 1);
    return photo(selected);
  }
}
