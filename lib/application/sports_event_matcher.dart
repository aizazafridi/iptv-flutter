import '../domain/sports.dart';
import '../domain/live_score.dart';

class SportsEventMatcher {
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll('\u00fc', 'u')
      .replaceAll('\u00f6', 'o')
      .replaceAll('\u00e4', 'a')
      .replaceAll('\u00df', 'ss')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static const aliases = {
    'ind': 'india',
    'pak': 'pakistan',
    'aus': 'australia',
    'eng': 'england',
    'nz': 'new zealand',
    'sa': 'south africa',
    'la lakers': 'los angeles lakers',
    'la clippers': 'los angeles clippers',
    'bayern munich': 'bayern munchen',
    'fc bayern munchen': 'bayern munchen',
    'borussia monchengladbach': 'borussia monchengladbach',
  };
  static String team(String value) {
    final n = normalize(value);
    return aliases[n] ?? n;
  }

  static String sport(String? value) =>
      normalize(value ?? '') == 'football' ? 'soccer' : normalize(value ?? '');
  static String competition(String? value) {
    final n = normalize(value ?? '');
    if ([
      'nba',
      'national basketball association',
      'nba basketball',
    ].contains(n)) {
      return 'nba';
    }
    if ([
      'german bundesliga',
      'bundesliga',
      '1 bundesliga',
      'german bundesliga 1',
    ].contains(n)) {
      return 'bundesliga';
    }
    return n;
  }

  bool? candidate(SportsEvent event, LiveScoreEvent score) {
    if (sport(event.sportId) != sport(score.sport) ||
        event.startTimeUtc == null ||
        score.startTimeUtc == null ||
        event.homeTeamName == null ||
        event.awayTeamName == null) {
      return null;
    }
    final a = event.startTimeUtc!.toUtc(), b = score.startTimeUtc!.toUtc();
    if (a.year != b.year ||
        a.month != b.month ||
        a.day != b.day ||
        a.difference(b).abs() > const Duration(minutes: 30)) {
      return null;
    }
    final league = competition(event.leagueName),
        other = competition(score.leagueName);
    // Missing competition evidence is intentionally insufficient to merge.
    if (league.isEmpty || other.isEmpty || league != other) return null;
    final home = team(event.homeTeamName!), away = team(event.awayTeamName!);
    if (home == team(score.homeTeamName) && away == team(score.awayTeamName)) {
      return false;
    }
    if (home == team(score.awayTeamName) && away == team(score.homeTeamName)) {
      return true;
    }
    return null;
  }

  Map<String, (LiveScoreEvent, bool)> match(
    List<SportsEvent> fixtures,
    List<LiveScoreEvent> scores,
  ) {
    final matches = <String, (LiveScoreEvent, bool)>{};
    final unique = {
      for (final score in scores)
        '${score.providerId}:${score.providerEventId}': score,
    }.values;
    for (final event in fixtures) {
      final candidates = <(LiveScoreEvent, bool)>[];
      for (final score in unique) {
        final reversed = candidate(event, score);
        if (reversed != null) candidates.add((score, reversed));
      }
      if (candidates.length != 1) continue;
      final chosen = candidates.single;
      if (fixtures.where((f) => candidate(f, chosen.$1) != null).length != 1) {
        continue;
      }
      matches[event.id] = chosen;
    }
    return matches;
  }
}
