import 'package:flutter/foundation.dart';
import '../domain/live_score.dart';
import '../domain/sports.dart';
import '../data/development_live_scores.dart';
import 'sports_event_matcher.dart';

class LiveScoreConfig {
  final String mode, cricketKey, nbaKey;
  final bool cricket, nba, openLiga;
  final int cricketBudget, devices;
  const LiveScoreConfig({
    this.mode = const String.fromEnvironment(
      'SPORTS_LIVE_SCORE_MODE',
      defaultValue: 'thesportsdb_only',
    ),
    this.cricket = const bool.fromEnvironment('CRICKETDATA_ENABLED'),
    this.nba = const bool.fromEnvironment('BALLDONTLIE_ENABLED'),
    this.openLiga = const bool.fromEnvironment('OPENLIGADB_ENABLED'),
    this.cricketKey = const String.fromEnvironment('CRICKETDATA_API_KEY'),
    this.nbaKey = const String.fromEnvironment('BALLDONTLIE_API_KEY'),
    this.cricketBudget = const int.fromEnvironment(
      'CRICKETDATA_DAILY_BUDGET',
      defaultValue: 75,
    ),
    this.devices = const int.fromEnvironment(
      'SPORTS_SCORE_ACTIVE_DEVICES',
      defaultValue: 1,
    ),
  });
  bool developmentAllowed(bool release) =>
      mode == 'development_multi_api' && !release;
}

class LiveScoreService {
  final SportsDataProvider primary;
  final LiveScoreConfig config;
  final List<LiveScoreProvider> providers;
  List<LiveScoreEvent> scores = [];
  final fixtures = <String, SportsEvent>{};
  int matched = 0, unmatched = 0, ambiguous = 0;
  bool closed = false;
  Future<void>? pending;
  LiveScoreService(
    this.primary, {
    this.config = const LiveScoreConfig(),
    List<LiveScoreProvider>? providers,
    bool release = kReleaseMode,
  }) : providers = config.developmentAllowed(release)
           ? (providers ??
                 [
                   if (config.cricket && config.cricketKey.isNotEmpty)
                     CricketDataLiveScoreProvider(
                       apiKey: config.cricketKey,
                       dailyBudget: config.cricketBudget.clamp(1, 100),
                       activeDevices: config.devices,
                     ),
                   if (config.nba && config.nbaKey.isNotEmpty)
                     BallDontLieLiveScoreProvider(apiKey: config.nbaKey),
                   if (config.openLiga) OpenLigaDbLiveScoreProvider(),
                 ])
           : [];
  bool get available => config.mode == 'thesportsdb_premium'
      ? primary.supportsLive
      : primary.supportsLive || providers.isNotEmpty;
  String? get providerNotice {
    final failed = providers
        .where((p) => p.error != null)
        .map((p) => '${p.providerId}: ${p.error}')
        .toList();
    return failed.isEmpty ? null : failed.join(' ');
  }

  SportsEvent latest(SportsEvent event) {
    if (!event.supplemental) return apply([event]).single;
    final update = scores
        .where(
          (s) =>
              s.providerId == event.scoreUpdate?.providerId &&
              s.providerEventId == event.scoreUpdate?.providerEventId,
        )
        .firstOrNull;
    return update == null ? event : event.withScore(update.snapshot());
  }

  String get unavailableMessage =>
      config.mode == 'thesportsdb_premium' && !primary.supportsLive
      ? 'TheSportsDB Premium live scores require a configured, supported backend.'
      : 'Live scores are not available with the current sports data plan.';
  Future<void> refresh() => pending ??= () async {
    if (closed) return;
    try {
      final batches = await Future.wait(
        providers.map((p) async {
          try {
            return await p.getLiveEvents();
          } catch (_) {
            return <LiveScoreEvent>[];
          }
        }),
      );
      scores = {
        for (final s in batches.expand((b) => b))
          '${s.providerId}:${s.providerEventId}': s,
      }.values.toList();
    } finally {
      pending = null;
    }
  }();
  List<SportsEvent> apply(List<SportsEvent> rows) {
    for (final row in rows.where((e) => !e.supplemental)) {
      fixtures[row.id] = row;
    }
    final associations = SportsEventMatcher().match(
      fixtures.values.toList(),
      scores,
    );
    matched = associations.length;
    unmatched = scores
        .where((s) => !associations.values.any((m) => identical(m.$1, s)))
        .length;
    ambiguous = scores
        .where(
          (s) =>
              fixtures.values
                  .where((f) => SportsEventMatcher().candidate(f, s) != null)
                  .length >
              1,
        )
        .length;
    return rows.map((event) {
      final found = associations[event.id];
      if (found == null) return event;
      final update = found.$1.snapshot(reversed: found.$2);
      // Preserve primary finished results and never replace newer primary data.
      if (event.status == SportsEventStatus.finished &&
          event.score != null &&
          (update.updatedAt == null ||
              event.lastUpdated == null ||
              !update.updatedAt!.isAfter(event.lastUpdated!))) {
        return event;
      }
      if (event.lastUpdated != null &&
          (update.updatedAt ?? update.fetchedAt).isBefore(event.lastUpdated!)) {
        return event;
      }
      if (event.scoreUpdate != null &&
          update.fetchedAt.isBefore(event.scoreUpdate!.fetchedAt)) {
        return event;
      }
      return event.withScore(update);
    }).toList();
  }

  Future<List<SportsEvent>> enrich(List<SportsEvent> rows) async {
    await refresh();
    return apply(rows);
  }

  Future<List<SportsEvent>> live(List<SportsEvent> primaryRows) async {
    if (config.mode != 'development_multi_api') {
      return primary.supportsLive ? primary.getLiveScores() : [];
    }
    final rows = await enrich(primaryRows);
    final matches = SportsEventMatcher().match(
      fixtures.values.toList(),
      scores,
    );
    final used = matches.values
        .map((m) => '${m.$1.providerId}:${m.$1.providerEventId}')
        .toSet();
    final result = rows
        .where((r) => r.scoreUpdate?.status == SportsEventStatus.live)
        .toList();
    final duplicateKeys = <String>{};
    for (final s in scores) {
      if (used.contains('${s.providerId}:${s.providerEventId}') ||
          s.status != SportsEventStatus.live) {
        continue;
      }
      final names = [
        SportsEventMatcher.team(s.homeTeamName),
        SportsEventMatcher.team(s.awayTeamName),
      ]..sort();
      final signature =
          '${s.sport}|${names.join('|')}|${SportsEventMatcher.competition(s.leagueName)}|${s.startTimeUtc}';
      if (!duplicateKeys.add(signature)) continue;
      result.add(
        SportsEvent(
          id: 'score:${s.providerId}:${s.providerEventId}',
          name: '${s.homeTeamName} vs ${s.awayTeamName}',
          sportId: s.sport,
          leagueName: s.leagueName,
          homeTeamName: s.homeTeamName,
          awayTeamName: s.awayTeamName,
          startTimeUtc: s.startTimeUtc,
          supplemental: true,
          scoreUpdate: s.snapshot(),
          status: SportsEventStatus.unknown,
        ),
      );
    }
    return result;
  }

  void diagnostics() {
    if (!kDebugMode) return;
    debugPrint(
      'Sports scores: primary=thesportsdb mode=${config.mode} matched=$matched unmatched=$unmatched ambiguous=$ambiguous',
    );
    debugPrint(
      'Sports scores configured: cricket=${config.cricket && config.cricketKey.isNotEmpty} nba=${config.nba && config.nbaKey.isNotEmpty} openligadb=${config.openLiga} api_football=false',
    );
    for (final p in providers) {
      debugPrint(
        'Sports scores: ${p.providerId} requests=${p.requestCount} lastSuccess=${p.lastSuccess} state=${p.error ?? 'ready'}',
      );
    }
  }

  void dispose() {
    closed = true;
    for (final p in providers) {
      p.dispose();
    }
  }
}
