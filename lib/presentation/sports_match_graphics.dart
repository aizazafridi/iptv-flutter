import 'package:flutter/material.dart';
import '../domain/sports.dart';
import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';

IconData sportsIcon(String? sport) => switch (sport) {
  'Cricket' => Icons.sports_cricket,
  'Soccer' || 'Football' => Icons.sports_soccer,
  'Basketball' => Icons.sports_basketball,
  'Tennis' => Icons.sports_tennis,
  'Motorsport' => Icons.sports_motorsports,
  _ => Icons.sports,
};

class SportsTeamIdentity extends StatelessWidget {
  final String name;
  final String? image;
  final bool lite;
  const SportsTeamIdentity({
    super.key,
    required this.name,
    this.image,
    required this.lite,
  });
  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    final fallback = Center(
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xff9acfff),
        ),
      ),
    );
    return Row(
      children: [
        if (!lite) ...[
          Container(
            width: 40,
            height: 40,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xff142e48),
              borderRadius: BorderRadius.circular(9),
            ),
            child: image == null
                ? fallback
                : SharedArtworkImage(
                    imageUrl:
                        Uri.tryParse(
                              image!,
                            )?.host.endsWith('thesportsdb.com') ==
                            true
                        ? '$image/tiny'
                        : image!,
                    kind: ArtworkKind.logo,
                    fit: BoxFit.contain,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class SportsScoreboard extends StatelessWidget {
  final SportsEvent event;
  final bool lite;
  const SportsScoreboard({super.key, required this.event, required this.lite});
  Widget innings(String? score) {
    if (score == null) {
      return const Text(
        '-',
        style: TextStyle(color: Colors.white54, fontSize: 20),
      );
    }
    final rows = score.split(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          Text(
            rows[i].replaceFirst(RegExp(r'\s+\([^)]*\)$'), ''),
            style: TextStyle(
              fontSize: rows.length > 2
                  ? 14
                  : rows.length > 1
                  ? 17
                  : 21,
              height: 1.05,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          if (RegExp(r'\(([^)]*)\)$').hasMatch(rows[i]))
            Text(
              '${rows.length > 1 ? 'Innings ${i + 1} - ' : ''}${RegExp(r'\(([^)]*)\)$').firstMatch(rows[i])!.group(1)} overs',
              style: const TextStyle(
                fontSize: 10,
                height: 1.1,
                color: Color(0xffb0c4dc),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = event.scoreUpdate?.homeScore ?? event.homeScore;
    final away = event.scoreUpdate?.awayScore ?? event.awayScore;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final side in [true, false]) ...[
          if (!side) const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SportsTeamIdentity(
                  name: side
                      ? event.homeTeamName ?? 'Participant 1'
                      : event.awayTeamName ?? 'Participant 2',
                  image: side
                      ? event.homeTeamLogo ?? event.scoreUpdate?.homeLogo
                      : event.awayTeamLogo ?? event.scoreUpdate?.awayLogo,
                  lite: lite,
                ),
                const SizedBox(height: 7),
                innings(side ? home : away),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
