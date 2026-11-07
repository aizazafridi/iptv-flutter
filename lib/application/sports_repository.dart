import '../domain/sports.dart';

/// UI uses normalized models only. Replace the adapter without changing widgets.
class SportsRepository {
  final SportsDataProvider provider;
  SportsRepository(this.provider);
  List<SportsEvent> unique(Iterable<SportsEvent> rows) =>
      {for (final row in rows) row.id: row}.values.toList()..sort(
        (a, b) => (a.startTimeUtc ?? DateTime.utc(9999)).compareTo(
          b.startTimeUtc ?? DateTime.utc(9999),
        ),
      );
  Future<List<SportsEvent>> today(DateTime localDate, {String? sport}) async {
    final begin = DateTime(localDate.year, localDate.month, localDate.day);
    final end = DateTime(localDate.year, localDate.month, localDate.day + 1);
    final first = begin.toUtc();
    final last = end.subtract(const Duration(microseconds: 1)).toUtc();
    final dates = <DateTime>[];
    for (
      var date = DateTime.utc(first.year, first.month, first.day);
      !date.isAfter(DateTime.utc(last.year, last.month, last.day));
      date = date.add(const Duration(days: 1))
    ) {
      dates.add(date);
    }
    final batches = await Future.wait(
      dates.map((d) => provider.getEventsByDate(d, sport: sport)),
    );
    return unique(
      batches
          .expand((x) => x)
          .where(
            (e) =>
                e.startTimeUtc != null &&
                !e.startTimeUtc!.isBefore(begin.toUtc()) &&
                e.startTimeUtc!.isBefore(end.toUtc()),
          ),
    );
  }

  Future<List<SportsEvent>> upcomingMotorsport(
    DateTime now,
    Iterable<SportsLeague> leagues, {
    String? leagueId,
  }) async {
    // The free league catalogue can omit motorsport entirely. 4370 is the
    // provider's Formula 1 league ID, not a locally invented race schedule.
    final ids = leagueId == null
        ? {
            '4370',
            ...leagues.where((l) => l.sportId == 'Motorsport').map((l) => l.id),
          }
        : {leagueId};
    final rows = <SportsEvent>[];
    Object? failure;
    var successful = false;
    for (final id in ids) {
      try {
        rows.addAll(await provider.getUpcomingEvents(leagueId: id));
        successful = true;
      } on SportsRequestCancelled {
        rethrow;
      } catch (e) {
        failure = e;
      }
    }
    final schedules = provider;
    if (schedules is SportsLeagueScheduleProvider) {
      // Per-league daily queries cover the race weekend even when the free
      // next-events endpoint returns only the first practice session.
      for (var offset = 0; offset < 8; offset++) {
        final date = now.toUtc().add(Duration(days: offset));
        try {
          rows.addAll(
            await (schedules as SportsLeagueScheduleProvider)
                .getLeagueEventsByDate(date, leagueId ?? '4370'),
          );
          successful = true;
        } on SportsRequestCancelled {
          rethrow;
        } catch (e) {
          failure = e;
        }
      }
    }
    if (!successful && failure != null) throw failure;
    return unique(
      rows.where(
        (e) =>
            e.sportId == 'Motorsport' &&
            e.startTimeUtc != null &&
            e.startTimeUtc!.isAfter(now.toUtc()) &&
            e.status != SportsEventStatus.finished &&
            e.status != SportsEventStatus.cancelled,
      ),
    );
  }

  Future<List<SportsEvent>> followed(
    Iterable<String> teams,
    Iterable<String> leagues, {
    bool results = false,
  }) async {
    final batches = await Future.wait([
      for (final id in teams)
        results
            ? provider.getRecentResults(teamId: id)
            : provider.getUpcomingEvents(teamId: id),
      for (final id in leagues)
        results
            ? provider.getRecentResults(leagueId: id)
            : provider.getUpcomingEvents(leagueId: id),
    ]);
    return unique(batches.expand((x) => x));
  }
}
