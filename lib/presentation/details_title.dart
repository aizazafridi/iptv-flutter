import 'package:flutter/material.dart';

/// Long fallback titles keep both lines inside fixed logo slots.
class DetailsTitle extends StatelessWidget {
  final String title;
  final double fontSize;
  final FontWeight weight;
  const DetailsTitle(
    this.title, {
    super.key,
    required this.fontSize,
    this.weight = FontWeight.w500,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: fontSize,
            height: 1.2,
            fontWeight: weight,
            color: Colors.white,
          ),
        ),
      );
      return constraints.hasBoundedHeight && constraints.hasBoundedWidth
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(width: constraints.maxWidth, child: text),
            )
          : text;
    },
  );
}
