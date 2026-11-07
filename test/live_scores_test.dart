import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_flutter/domain/sports.dart';
import 'package:iptv_flutter/domain/live_score.dart';
import 'package:iptv_flutter/data/development_live_scores.dart';
import 'package:iptv_flutter/application/live_score_service.dart';
import 'package:iptv_flutter/application/sports_event_matcher.dart';
import 'sports_hub_test.dart' show SportsFixtureApi;

class StubScores implements LiveScoreProvider {
  List<LiveScoreEvent> rows;
  int calls = 0;
  StubScores(this.rows);
  @override
  String get providerId => 'test';
  @override
  Duration get refreshInterval => const Duration(minutes: 2);
  @override
  String? get error => null;
  @override
  int get requestCount => calls;
  @override
  DateTime? get lastSuccess => null;
  @override
  Future<List<LiveScoreEvent>> getLiveEvents() async {
    calls++;
    return rows;
  }

  @override
  Future<LiveScoreEvent?> getEventScore(SportsEvent event) async => null;
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final start = DateTime.utc(2026, 11, 6, 18);
  SportsEvent fixture({
    String id = 'primary',
    String league = 'World Cup',
    DateTime? time,
    String home = 'India',
    String away = 'Pakistan',
  }) => SportsEvent(
    id: id,
    name: '$home vs $away',
    sportId: 'Cricket',
    leagueName: league,
    homeTeamName: home,
    awayTeamName: away,
    startTimeUtc: time ?? start,
  );
  LiveScoreEvent score({
    String id = 'score',
    String home = 'India',
    String away = 'Pakistan',
    String league = 'World Cup',
    DateTime? time,
    DateTime? fetched,
  }) => LiveScoreEvent(
    providerId: 'cricketdata',
    providerEventId: id,
    sport: 'Cricket',
    leagueName: league,
    homeTeamName: home,
    awayTeamName: away,
    startTimeUtc: time ?? start,
    fetchedAt: fetched ?? DateTime.now().toUtc(),
    freshUntil: (fetched ?? DateTime.now().toUtc()).add(
      const Duration(minutes: 5),
    ),
    status: SportsEventStatus.live,
    homeScore: '185/4 (18.3)',
    awayScore: '179/8 (20.0)',
  );
  Map cricket() => {
    'status': 'success',
    'data': [
      {
        'id': 'c1',
        'teams': ['India', 'Pakistan'],
        'dateTimeGMT': '2026-11-06T18:00:00',
        'matchStarted': true,
        'matchEnded': false,
        'score': [
          {'inning': 'India Inning 1', 'r': 185, 'w': 4, 'o': 18.3},
          {'inning': 'Pakistan Inning 1', 'r': 179, 'w': 8, 'o': 20.0},
        ],
      },
    ],
  };
  test(
    'CricketData WI/BAN combined label recovers the uniquely missing innings owner',
    () {
      final raw = {
        'data': [
          {
            'id': 'wi-ban',
            'teams': ['Bangladesh', 'West Indies'],
            'score': [
              {'r': 356, 'w': 10, 'o': 106.4, 'inning': 'west indies Inning 1'},
              {
                'r': 88,
                'w': 3,
                'o': 40,
                'inning': 'Bangladesh,West Indies Inning 1',
              },
            ],
          },
        ],
      };
      final e = CricketDataLiveScoreProvider.parse(
        raw,
        DateTime.now(),
        const Duration(minutes: 5),
      ).single;
      expect(e.homeTeamName, 'Bangladesh');
      expect(e.homeScore, '88/3 (40)');
      expect(e.awayScore, '356/10 (106.4)');
      (raw['data'] as List).single['teams'] = ['West Indies', 'Bangladesh'];
      final reversed = CricketDataLiveScoreProvider.parse(
        raw,
        DateTime.now(),
        const Duration(minutes: 5),
      ).single;
      expect(reversed.homeScore, '356/10 (106.4)');
      expect(reversed.awayScore, '88/3 (40)');
    },
  );
  test('combined labels without unique innings evidence remain unassigned', () {
    final raw = {
      'data': [
        {
          'id': 'ambiguous',
          'teams': ['Bangladesh', 'West Indies'],
          'score': [
            {'r': 356, 'inning': 'Bangladesh,West Indies Inning 1'},
            {'r': 88, 'inning': 'West Indies,Bangladesh Inning 1'},
          ],
        },
      ],
    };
    final e = CricketDataLiveScoreProvider.parse(
      raw,
      DateTime.now(),
      Duration.zero,
    ).single;
    expect(e.homeScore, isNull);
    expect(e.awayScore, isNull);
  });
  test(
    'known primary final scores cannot be overwritten by undated supplemental snapshots',
    () async {
      final primary = SportsEvent(
        id: 'primary',
        name: 'India vs Pakistan',
        sportId: 'Cricket',
        leagueName: 'World Cup',
        homeTeamName: 'India',
        awayTeamName: 'Pakistan',
        startTimeUtc: start,
        status: SportsEventStatus.finished,
        homeScore: '200',
        awayScore: '190',
      );
      final service = LiveScoreService(
        SportsFixtureApi(),
        config: const LiveScoreConfig(mode: 'development_multi_api'),
        providers: [
          StubScores([score()]),
        ],
      );
      final result = (await service.enrich([primary])).single;
      expect(result.scoreUpdate, isNull);
      expect(result.displayScore, '200 - 190');
      service.dispose();
    },
  );
  test(
    'duplicate provider IDs deduplicate and missing competitions do not merge',
    () {
      expect(
        SportsEventMatcher().match([fixture()], [score(), score()]),
        hasLength(1),
      );
      expect(
        SportsEventMatcher().match([fixture(league: '')], [score()]),
        isEmpty,
      );
    },
  );
  test('Cricket innings keep correct teams, wickets and overs', () {
    final e = CricketDataLiveScoreProvider.parse(
      cricket(),
      DateTime.now().toUtc(),
      const Duration(minutes: 5),
    ).single;
    expect(e.homeScore, '185/4 (18.3)');
    expect(e.awayScore, '179/8 (20.0)');
    expect(e.status, SportsEventStatus.live);
    expect(e.startTimeUtc, start);
    expect(e.sportSpecificData['innings'], hasLength(2));
  });
  test(
    'cricket multiple innings and unknown score ownership are not flattened',
    () {
      final raw = cricket();
      (raw['data'] as List).single['score'] = [
        {'inning': 'India Inning 1', 'r': 180},
        {'inning': 'India Inning 2', 'r': 100, 'w': 2},
        {'inning': 'Unknown Inning 1', 'r': 99},
      ];
      final e = CricketDataLiveScoreProvider.parse(
        raw,
        DateTime.now().toUtc(),
        const Duration(minutes: 5),
      ).single;
      expect(e.homeScore, '180 / 100/2');
      expect(e.awayScore, isNull);
    },
  );
  test('Cricket missing teams skipped, missing scores/times remain absent', () {
    expect(
      CricketDataLiveScoreProvider.parse(
        {
          'data': [
            {'id': '1'},
          ],
        },
        DateTime.now(),
        Duration.zero,
      ),
      isEmpty,
    );
    final e = CricketDataLiveScoreProvider.parse(
      {
        'data': [
          {
            'id': '1',
            'teams': ['India', 'Pakistan'],
          },
        ],
      },
      DateTime.now(),
      Duration.zero,
    ).single;
    expect(e.homeScore, isNull);
    expect(e.startTimeUtc, isNull);
    expect(e.status, SportsEventStatus.unknown);
  });
  test('NBA authentication endpoint, date parameters and caching', () async {
    var calls = 0;
    final api = BallDontLieLiveScoreProvider(
      apiKey: 'fixture-key',
      client: MockClient((r) async {
        calls++;
        expect(r.headers['Authorization'], 'fixture-key');
        expect(r.url.path, '/v1/games');
        expect(r.url.queryParametersAll['dates[]'], hasLength(2));
        return http.Response('{"data":[]}', 200);
      }),
    );
    await Future.wait([api.getLiveEvents(), api.getLiveEvents()]);
    await api.getLiveEvents();
    expect(calls, 1);
    api.dispose();
  });
  test('NBA period/status and correct home/visitor assignment', () {
    final e = BallDontLieLiveScoreProvider.parse(
      {
        'data': [
          {
            'id': 1,
            'home_team': {'full_name': 'Los Angeles Lakers'},
            'visitor_team': {'full_name': 'Boston Celtics'},
            'status_state': 'in',
            'period': 4,
            'time': '3:42',
            'home_team_score': 105,
            'visitor_team_score': 98,
            'datetime': '2026-11-06T18:00:00Z',
          },
        ],
      },
      DateTime.now(),
      const Duration(minutes: 2),
    ).single;
    expect(e.status, SportsEventStatus.live);
    expect(e.homeScore, '105');
    expect(e.awayScore, '98');
    expect(e.period, '4');
    expect(e.clock, '3:42');
  });
  test(
    'NBA missing names ignored; missing status does not become live from clock',
    () {
      expect(
        BallDontLieLiveScoreProvider.parse(
          {
            'data': [
              {'id': 1},
            ],
          },
          DateTime.now(),
          Duration.zero,
        ),
        isEmpty,
      );
      final e = BallDontLieLiveScoreProvider.parse(
        {
          'data': [
            {
              'id': 1,
              'home_team': {'full_name': 'A'},
              'visitor_team': {'full_name': 'B'},
              'period': 4,
            },
          ],
        },
        DateTime.now(),
        Duration.zero,
      ).single;
      expect(e.status, SportsEventStatus.unknown);
      expect(e.startTimeUtc, isNull);
    },
  );
  test(
    'OpenLiga final result selected by result type, unfinished never inferred live',
    () {
      final raw = [
        {
          'matchID': 1,
          'leagueShortcut': 'bl1',
          'team1': {'teamName': 'Bayern'},
          'team2': {'teamName': 'Dortmund'},
          'matchDateTimeUTC': '2026-11-06T18:00:00Z',
          'matchIsFinished': false,
          'matchResults': [
            {'resultTypeID': 1, 'pointsTeam1': 0, 'pointsTeam2': 1},
            {'resultTypeID': 2, 'pointsTeam1': 2, 'pointsTeam2': 1},
          ],
        },
      ];
      final e = OpenLigaDbLiveScoreProvider.parse(
        raw,
        DateTime.now(),
        const Duration(minutes: 5),
      ).single;
      expect(e.homeScore, '2');
      expect(e.awayScore, '1');
      expect(e.status, SportsEventStatus.unknown);
      raw.single['matchIsFinished'] = true;
      expect(
        OpenLigaDbLiveScoreProvider.parse(
          raw,
          DateTime.now(),
          Duration.zero,
        ).single.status,
        SportsEventStatus.finished,
      );
    },
  );
  test(
    'OpenLiga skips missing participants and keeps missing timestamps unknown',
    () {
      expect(
        OpenLigaDbLiveScoreProvider.parse(
          [
            {'matchID': 1},
          ],
          DateTime.now(),
          Duration.zero,
        ),
        isEmpty,
      );
      final e = OpenLigaDbLiveScoreProvider.parse(
        [
          {
            'matchID': 1,
            'team1': {'teamName': 'A'},
            'team2': {'teamName': 'B'},
          },
        ],
        DateTime.now(),
        Duration.zero,
      ).single;
      expect(e.startTimeUtc, isNull);
      expect(e.homeScore, isNull);
    },
  );
  for (final code in [400, 401, 403, 404, 429, 500, 503]) {
    test(
      'HTTP $code backed off without crashing fixtures or exposing credentials',
      () async {
        var calls = 0;
        final api = BallDontLieLiveScoreProvider(
          apiKey: 'fixture-secret',
          client: MockClient((_) async {
            calls++;
            return http.Response('', code);
          }),
        );
        expect(await api.getLiveEvents(), isEmpty);
        await api.getLiveEvents();
        expect(calls, 1);
        expect(api.error, isNotNull);
        expect(api.error, isNot(contains('fixture-secret')));
        api.dispose();
      },
    );
  }
  test('timeouts and invalid JSON preserve last known scores', () async {
    var now = DateTime.now().toUtc(), calls = 0;
    final api = OpenLigaDbLiveScoreProvider(
      now: () => now,
      client: MockClient((_) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode([
              {
                'matchID': 1,
                'team1': {'teamName': 'A'},
                'team2': {'teamName': 'B'},
              },
            ]),
            200,
          );
        }
        throw TimeoutException('secret-url');
      }),
    );
    expect(await api.getLiveEvents(), hasLength(1));
    now = now.add(const Duration(minutes: 6));
    expect(await api.getLiveEvents(), hasLength(1));
    expect(api.error, 'Unable to refresh scores.');
    api.dispose();
    final malformed = OpenLigaDbLiveScoreProvider(
      client: MockClient((_) async => http.Response('broken', 200)),
    );
    expect(await malformed.getLiveEvents(), isEmpty);
    expect(malformed.error, isNotNull);
    malformed.dispose();
  });
  test(
    'cricket daily quota persisted across adapter recreation and polling interval budgeted',
    () async {
      var now = DateTime.utc(2026, 11, 6);
      var calls = 0;
      CricketDataLiveScoreProvider api() => CricketDataLiveScoreProvider(
        apiKey: 'fixture',
        dailyBudget: 1,
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response('{"status":"success","data":[]}', 200);
        }),
      );
      final first = api();
      expect(first.refreshInterval.inSeconds, 86400);
      await first.getLiveEvents();
      first.dispose();
      final second = api();
      await second.getLiveEvents();
      expect(calls, 1);
      expect(second.error, contains('budget'));
      second.dispose();
    },
  );
  test(
    'cricket API failure/quota status never treated as valid empty live result',
    () async {
      final api = CricketDataLiveScoreProvider(
        apiKey: 'fixture',
        client: MockClient(
          (_) async =>
              http.Response('{"status":"failure","reason":"quota"}', 200),
        ),
      );
      expect(await api.getLiveEvents(), isEmpty);
      expect(api.error, isNotNull);
      api.dispose();
    },
  );
  test(
    'matching exact teams and league preserves primary ID and external metadata',
    () async {
      final service = LiveScoreService(
        SportsFixtureApi(),
        config: const LiveScoreConfig(mode: 'development_multi_api'),
        providers: [
          StubScores([score()]),
        ],
      );
      final merged = (await service.enrich([fixture()])).single;
      expect(merged.id, 'primary');
      expect(merged.scoreUpdate!.providerEventId, 'score');
      expect(merged.displayScore, '185/4 (18.3) - 179/8 (20.0)');
      expect(merged.scoreIsLive, isTrue);
      service.dispose();
    },
  );
  test('aliases and reversed sides remap scores to correct team', () async {
    final service = LiveScoreService(
      SportsFixtureApi(),
      config: const LiveScoreConfig(mode: 'development_multi_api'),
      providers: [
        StubScores([score(home: 'PAK', away: 'IND')]),
      ],
    );
    final e = (await service.enrich([fixture()])).single;
    expect(e.scoreUpdate!.homeScore, '179/8 (20.0)');
    expect(e.scoreUpdate!.awayScore, '185/4 (18.3)');
    service.dispose();
  });
  test(
    'conflicting competition/date/start and missing start reject matching',
    () {
      final matcher = SportsEventMatcher();
      expect(matcher.match([fixture(league: 'Other Cup')], [score()]), isEmpty);
      expect(
        matcher.match(
          [fixture(time: start.add(const Duration(days: 1)))],
          [score()],
        ),
        isEmpty,
      );
      expect(
        matcher.match(
          [fixture(time: start.add(const Duration(hours: 2)))],
          [score()],
        ),
        isEmpty,
      );
      expect(
        matcher.match(
          [
            const SportsEvent(
              id: 'no-time',
              name: 'India vs Pakistan',
              sportId: 'Cricket',
              leagueName: 'World Cup',
              homeTeamName: 'India',
              awayTeamName: 'Pakistan',
            ),
          ],
          [score()],
        ),
        isEmpty,
      );
    },
  );
  test('duplicate fixtures and competing candidates remain ambiguous', () {
    final matcher = SportsEventMatcher();
    expect(
      matcher.match([fixture(), fixture(id: 'second')], [score()]),
      isEmpty,
    );
    expect(matcher.match([fixture()], [score(), score(id: 'second')]), isEmpty);
  });
  test('different basketball competition cannot inherit NBA scores', () {
    final s = LiveScoreEvent(
      providerId: 'balldontlie',
      providerEventId: '1',
      sport: 'Basketball',
      leagueName: 'NBA',
      homeTeamName: 'A',
      awayTeamName: 'B',
      startTimeUtc: start,
      fetchedAt: DateTime.now(),
      freshUntil: DateTime.now(),
    );
    expect(
      SportsEventMatcher().match(
        [
          SportsEvent(
            id: '1',
            name: 'A vs B',
            sportId: 'Basketball',
            leagueName: 'EuroLeague',
            homeTeamName: 'A',
            awayTeamName: 'B',
            startTimeUtc: start,
          ),
        ],
        [s],
      ),
      isEmpty,
    );
  });
  for (final mode in ['thesportsdb_only', 'thesportsdb_premium']) {
    test(
      '$mode disables all development calls, including configured adapters',
      () async {
        final stub = StubScores([score()]);
        final service = LiveScoreService(
          SportsFixtureApi(),
          config: LiveScoreConfig(mode: mode),
          providers: [stub],
        );
        await service.enrich([fixture()]);
        expect(stub.calls, 0);
        expect(service.providers, isEmpty);
        if (mode == 'thesportsdb_premium') {
          expect(service.unavailableMessage, contains('backend'));
        }
        service.dispose();
      },
    );
  }
  test('release builds reject development mode', () async {
    final stub = StubScores([score()]);
    final service = LiveScoreService(
      SportsFixtureApi(),
      config: const LiveScoreConfig(mode: 'development_multi_api'),
      providers: [stub],
      release: true,
    );
    await service.enrich([fixture()]);
    expect(stub.calls, 0);
    service.dispose();
  });
  test(
    'missing keys skip optional providers while keyless OpenLiga can be enabled',
    () {
      final service = LiveScoreService(
        SportsFixtureApi(),
        config: const LiveScoreConfig(
          mode: 'development_multi_api',
          cricket: true,
          nba: true,
          openLiga: true,
        ),
      );
      expect(service.providers.map((p) => p.providerId), ['openligadb']);
      service.dispose();
    },
  );
  test('stale scores remain on Today but no longer count as live', () async {
    final old = score(
      fetched: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    final service = LiveScoreService(
      SportsFixtureApi(),
      config: const LiveScoreConfig(mode: 'development_multi_api'),
      providers: [
        StubScores([old]),
      ],
    );
    final e = (await service.enrich([fixture()])).single;
    expect(e.displayScore, isNotNull);
    expect(e.scoreIsLive, isFalse);
    expect(e.scoreUpdate!.label, contains('Last known'));
    expect(
      (await service.live([fixture()])).single.scoreUpdate!.fresh,
      isFalse,
    );
    service.dispose();
  });
  test(
    'unmatched live supplemental card never inherits fixture IDs or logos',
    () async {
      final service = LiveScoreService(
        SportsFixtureApi(),
        config: const LiveScoreConfig(mode: 'development_multi_api'),
        providers: [
          StubScores([score(league: 'Unknown')]),
        ],
      );
      final rows = await service.live([fixture()]);
      expect(rows.single.id, 'score:cricketdata:score');
      expect(rows.single.supplemental, isTrue);
      expect(rows.single.homeTeamId, isNull);
      expect(rows.single.homeTeamLogo, isNull);
      service.dispose();
    },
  );
}
