import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SourceRatingBadge extends StatelessWidget {
  final String source, asset;
  final String? value;
  final double scale;
  const SourceRatingBadge({
    super.key,
    required this.source,
    required this.asset,
    required this.value,
    required this.scale,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$source ${value ?? 'rating unavailable'}',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            asset,
            height: 24 * scale,
            width: (source == 'IMDb' ? 48 : 24) * scale,
          ),
          const SizedBox(width: 7),
          Text(
            value ?? 'Unavailable',
            style: TextStyle(
              color: value == null ? Colors.white54 : Colors.white,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
