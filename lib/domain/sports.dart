enum SportsEventStatus {
  scheduled,
  live,
  finished,
  postponed,
  cancelled,
  unknown,
}

class Sport {
  final String id, name;
  final String? description, thumbnailUrl;
  const Sport(this.id, this.name, {this.description, this.thumbnailUrl});
  String get displayName => name == 'Soccer' ? 'Football' : name;
}

class SportsLeague {
  final String id, name;
  final String? sportId, country, logoUrl, currentSeason;
  const SportsLeague(
    this.id,
    this.name, {
    this.sportId,
    this.country,
    this.logoUrl,
    this.currentSeason,
  });
}

class SportsTeam {
  final String id, name;
  final String? sportId, leagueId, country, logoUrl;
  const SportsTeam(
    this.id,
    this.name, {
    this.sportId,
    this.leagueId,
    this.country,
    this.logoUrl,
  });
}

class SportsEvent {
  final String id, name;
  final SportsScoreSnapshot? scoreUpdate;
  final bool supplemental;
  final String? sportId,
      leagueId,
      leagueName,
      homeTeamId,
      awayTeamId,
      homeTeamName,
      awayTeamName,
      homeTeamLogo,
      awayTeamLogo;
  final DateTime? startTimeUtc, lastUpdated;
  final SportsEventStatus status;
  // Strings preserve sport-specific provider values, including wickets/overs.
  final String? homeScore, awayScore, scoreDetail, venue, round, season;
  const SportsEvent({
    required this.id,
    required this.name,
    this.scoreUpdate,
    this.supplemental = false,
    this.sportId,
    this.leagueId,
    this.leagueName,
    this.homeTeamId,
    this.awayTeamId,
    this.homeTeamName,
    this.awayTeamName,
    this.homeTeamLogo,
    this.awayTeamLogo,
    this.startTimeUtc,
    this.lastUpdated,
    this.status = SportsEventStatus.unknown,
    this.homeScore,
    this.awayScore,
    this.scoreDetail,
    this.venue,
    this.round,
    this.season,
  });
  String get primaryEventProvider =>
      supplemental ? scoreUpdate?.providerId ?? 'unknown' : 'thesportsdb';
  SportsEvent withScore(SportsScoreSnapshot update) => SportsEvent(
    id: id,
    name: name,
    sportId: sportId,
    leagueId: leagueId,
    leagueName: leagueName,
    homeTeamId: homeTeamId,
    awayTeamId: awayTeamId,
    homeTeamName: homeTeamName,
    awayTeamName: awayTeamName,
    homeTeamLogo: homeTeamLogo,
    awayTeamLogo: awayTeamLogo,
    startTimeUtc: startTimeUtc,
    lastUpdated: lastUpdated,
    status: status,
    homeScore: homeScore,
    awayScore: awayScore,
    scoreDetail: scoreDetail,
    venue: venue,
    round: round,
    season: season,
    scoreUpdate: update,
    supplemental: supplemental,
  );
  String? get displayScore => scoreUpdate?.score ?? score;
  bool get scoreIsLive =>
      scoreUpdate?.fresh == true &&
      scoreUpdate?.status == SportsEventStatus.live;
  String? get score => homeScore != null && awayScore != null
      ? '$homeScore - $awayScore'
      : homeScore ?? awayScore;
}

class SportsDataException implements Exception {
  final String message;
  const SportsDataException(this.message);
  @override
  String toString() => message;
}

abstract interface class SportsDataProvider {
  bool get supportsLive;
  bool get limitedCoverage;
  String get attribution;
  Future<List<Sport>> getSports();
  Future<List<SportsLeague>> getLeagues();
  Future<SportsLeague?> getLeagueDetails(String id);
  Future<List<SportsEvent>> getEventsByDate(DateTime date, {String? sport});
  Future<List<SportsEvent>> getUpcomingEvents({
    String? leagueId,
    String? teamId,
  });
  Future<List<SportsEvent>> getRecentResults({
    String? leagueId,
    String? teamId,
  });
  Future<List<SportsTeam>> getTeams(String query);
  Future<SportsTeam?> getTeamDetails(String id);
  Future<SportsEvent?> getEventDetails(String id);
  Future<List<SportsEvent>> getLiveScores();
  void dispose();
}

class SportsRequestCancelled extends SportsDataException {
  const SportsRequestCancelled() : super('Sports request cancelled.');
}

class SportsScoreSnapshot {
  final String providerId, providerEventId, confidence;
  final DateTime fetchedAt, freshUntil;
  final DateTime? updatedAt;
  final SportsEventStatus status;
  final String? homeScore, awayScore, period, clock, detail, homeLogo, awayLogo;
  const SportsScoreSnapshot({
    required this.providerId,
    required this.providerEventId,
    required this.fetchedAt,
    required this.freshUntil,
    required this.status,
    this.confidence = 'high',
    this.homeLogo,
    this.awayLogo,
    this.updatedAt,
    this.homeScore,
    this.awayScore,
    this.period,
    this.clock,
    this.detail,
  });
  bool get fresh =>
      DateTime.now().toUtc().isBefore(freshUntil) &&
      (updatedAt == null ||
          fetchedAt.difference(updatedAt!).abs() < const Duration(minutes: 15));
  String? get score => homeScore != null && awayScore != null
      ? '$homeScore - $awayScore'
      : homeScore ?? awayScore;
  String get label =>
      '${fresh ? 'Score' : 'Last known score'}: $providerId - fetched ${DateTime.now().toUtc().difference(fetchedAt).inMinutes.clamp(0, 999999)} min ago';
}

/// Optional capability for league-filtered schedules, avoiding daily free-tier truncation.
abstract interface class SportsLeagueScheduleProvider {
  Future<List<SportsEvent>> getLeagueEventsByDate(
    DateTime date,
    String leagueId,
  );
}
