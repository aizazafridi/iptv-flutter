import '../domain/models.dart';
import '../domain/sports.dart';

enum SportsChannelConfidence { verified, possible, related }

class SportsChannelMatch {
  final ContentItem channel;
  final SportsChannelConfidence confidence;
  final String evidence;
  const SportsChannelMatch(this.channel, this.confidence, this.evidence);
}

/// IDs remain provider-scoped through the caller's connected provider. Names
/// are only evidence for discovery, never used to resolve a playback source.
class SportsChannelMatcher {
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'\b(hd|fhd|uhd|4k|8k)\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static bool sportsChannel(String name) => RegExp(
    r'\b(sports?|espn|willow|cricket|cric|soccer|football|basketball|tennis|baseball|hockey|motorsport|bein|dazn|eurosport|tsn)\b',
  ).hasMatch(normalize(name));
  static bool mentions(String haystack, String? phrase) {
    if (phrase == null) return false;
    final normalized = normalize(phrase);
    return normalized.length >= 3 && ' $haystack '.contains(' $normalized ');
  }

  List<SportsChannelMatch> match(
    SportsEvent event,
    List<ContentItem> channels,
    Map<String, List<EpgProgramme>> epg,
  ) {
    final matches = <SportsChannelMatch>[];
    for (final channel in channels) {
      SportsChannelMatch? best;
      for (final programme in epg[channel.id] ?? <EpgProgramme>[]) {
        final title = normalize(programme.title);
        if (RegExp(r'\b(highlights?|replay|repeat|classic)\b').hasMatch(title)) {
          continue;
        }
        final start = event.startTimeUtc;
        if (start == null ||
            start.isBefore(
              programme.start.subtract(const Duration(minutes: 15)),
            ) ||
            !start.isBefore(programme.end)) {
          continue;
        }
        final home = mentions(title, event.homeTeamName);
        final away = mentions(title, event.awayTeamName);
        final competition = mentions(
          normalize('${programme.title} ${programme.description}'),
          event.leagueName,
        );
        if (home && away && competition) {
          best = SportsChannelMatch(
            channel,
            SportsChannelConfidence.verified,
            'EPG names both teams and competition at the scheduled time.',
          );
          break;
        }
        if (home && away) {
          best = SportsChannelMatch(
            channel,
            SportsChannelConfidence.possible,
            'EPG names both teams at the scheduled time; competition is unconfirmed.',
          );
        }
      }
      if (best != null) {
        matches.add(best);
      } else if (sportsChannel(channel.name)) {
        matches.add(
          SportsChannelMatch(
            channel,
            SportsChannelConfidence.related,
            'Sports channel; broadcast of this event is not confirmed.',
          ),
        );
      }
    }
    matches.sort((a, b) => a.confidence.index.compareTo(b.confidence.index));
    return matches;
  }
}
