import 'sports.dart';

class LiveScoreEvent {
  final String providerId, providerEventId, sport, homeTeamName, awayTeamName;
  final String? homeLogo, awayLogo;
  final String? leagueName,
      leagueId,
      homeScore,
      awayScore,
      period,
      clock,
      detail;
  final DateTime? startTimeUtc, lastUpdatedUtc;
  final DateTime fetchedAt, freshUntil;
  final SportsEventStatus status;
  final Map<String, dynamic> sportSpecificData;
  const LiveScoreEvent({
    required this.providerId,
    required this.providerEventId,
    required this.sport,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.fetchedAt,
    required this.freshUntil,
    this.homeLogo,
    this.awayLogo,
    this.leagueName,
    this.leagueId,
    this.startTimeUtc,
    this.lastUpdatedUtc,
    this.status = SportsEventStatus.unknown,
    this.homeScore,
    this.awayScore,
    this.period,
    this.clock,
    this.detail,
    this.sportSpecificData = const {},
  });
  SportsScoreSnapshot snapshot({bool reversed = false}) => SportsScoreSnapshot(
    providerId: providerId,
    providerEventId: providerEventId,
    fetchedAt: fetchedAt,
    freshUntil: freshUntil,
    updatedAt: lastUpdatedUtc,
    status: status,
    homeLogo: reversed ? awayLogo : homeLogo,
    awayLogo: reversed ? homeLogo : awayLogo,
    homeScore: reversed ? awayScore : homeScore,
    awayScore: reversed ? homeScore : awayScore,
    period: period,
    clock: clock,
    detail: detail,
  );
}

abstract interface class LiveScoreProvider {
  String get providerId;
  Duration get refreshInterval;
  String? get error;
  int get requestCount;
  DateTime? get lastSuccess;
  Future<List<LiveScoreEvent>> getLiveEvents();
  Future<LiveScoreEvent?> getEventScore(SportsEvent event);
  void dispose();
}
