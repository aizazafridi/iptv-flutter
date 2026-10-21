import 'package:flutter/material.dart';
import '../domain/models.dart';

/// Decorative artwork stays local, so the home screen opens without downloads.
class HomeCategoryCard extends StatefulWidget {
  final ContentType type;
  final VoidCallback onTap;
  const HomeCategoryCard({super.key, required this.type, required this.onTap});
  @override
  State<HomeCategoryCard> createState() => _HomeCategoryCardState();
}

class _HomeCategoryCardState extends State<HomeCategoryCard> {
  bool focused = false;
  bool hovered = false;
  @override
  Widget build(BuildContext context) {
    final (accent, base, icon, caption, badge) = switch (widget.type) {
      ContentType.live => (
        const Color(0xff5ce4ed),
        const Color(0xff123c53),
        Icons.satellite_alt_rounded,
        'Tune into the moment',
        'ON AIR',
      ),
      ContentType.movies => (
        const Color(0xffffc17a),
        const Color(0xff573246),
        Icons.local_movies_rounded,
        'Make it a movie night',
        'CINEMA',
      ),
      ContentType.series => (
        const Color(0xffc4a3ff),
        const Color(0xff352660),
        Icons.video_library_rounded,
        'Find your next obsession',
        'EPISODES',
      ),
    };
    final active = focused || hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(5),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [base, const Color(0xff141321)],
          ),
          border: Border.all(
            color: focused
                ? Colors.white
                : accent.withValues(alpha: active ? 0.8 : 0.3),
            width: focused ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: active ? 0.22 : 0.07),
              blurRadius: active ? 28 : 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            autofocus: widget.type == ContentType.live,
            onFocusChange: (value) => setState(() => focused = value),
            onTap: widget.onTap,
            hoverColor: accent.withValues(alpha: 0.06),
            focusColor: accent.withValues(alpha: 0.08),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Positioned(
                    right: -32,
                    top: 40,
                    child: ExcludeSemantics(
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Icon(
                          icon,
                          size: 110,
                          color: accent.withValues(alpha: 0.07),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              badge,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                letterSpacing: 2.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(icon, size: 26, color: accent),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.type.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xffc5c2d3),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
