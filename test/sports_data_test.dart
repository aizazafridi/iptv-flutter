import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_flutter/domain/sports.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/the_sports_db_provider.dart';
import 'package:iptv_flutter/data/sports_api_cache.dart';
import 'package:iptv_flutter/application/sports_favorites.dart';
import 'package:iptv_flutter/application/sports_channel_matcher.dart';
import 'package:iptv_flutter/application/sports_repository.dart';

Map<String, dynamic> fixture({String id = '42', String? status = 'NS'}) => {
  'idEvent': id,
  'strEvent': 'Arsenal vs Chelsea',
  'strSport': 'Soccer',
  'idLeague': '4328',
  'strLeague': 'Premier League',
  'idHomeTeam': '1',
  'idAwayTeam': '2',
  'strHomeTeam': 'Arsenal',
  'strAwayTeam': 'Chelsea',
  'strTimestamp': '2026-11-05T20:00:00',
  'strStatus': status,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  TheSportsDbProvider adapter(
    Future<http.Response> Function(http.Request) handler, {
    Future<void> Function(Duration)? wait,
    Duration? timeout,
  }) => TheSportsDbProvider(
    client: MockClient(handler),
    wait: wait ?? (_) async {},
    timeout: timeout ?? const Duration(seconds: 1),
  );
  test('obsolete queued schedules are skipped before HTTP starts', () async {
    final gate = Completer<http.Response>();
    final paths = <String>[];
    final p = adapter((r) async {
      paths.add(r.url.path);
      if (r.url.path.contains('all_sports')) return gate.future;
      return http.Response('{"events":[]}', 200);
    });
    final metadata = p.getSports();
    final obsolete = p.getEventsByDate(DateTime(2026, 11, 5));
    final checked = expectLater(
      obsolete,
      throwsA(isA<SportsRequestCancelled>()),
    );
    await Future<void>.delayed(Duration.zero);
    p.cancelQueuedSchedules();
    gate.complete(http.Response('{"sports":[]}', 200));
    await metadata;
    await checked;
    expect(paths.length, 1);
    expect(await p.getEventsByDate(DateTime(2026, 11, 6)), isEmpty);
    expect(paths.length, 2);
    p.dispose();
  });
  test('sports and league endpoints normalize IDs and display names', () async {
    final p = adapter(
      (r) async => http.Response(
        jsonEncode(
          r.url.path.contains('all_sports')
              ? {
                  'sports': [
                    {'idSport': '102', 'strSport': 'Soccer'},
                  ],
                }
              : {
                  'leagues': [
                    {
                      'idLeague': '4328',
                      'strLeague': 'Premier League',
                      'strSport': 'Soccer',
                    },
                  ],
                },
        ),
        200,
      ),
    );
    expect((await p.getSports()).single.displayName, 'Football');
    expect((await p.getLeagues()).single.id, '4328');
    p.dispose();
  });
  test(
    'daily fixtures use dynamic date and provider sport and deduplicate IDs',
    () async {
      final p = adapter((r) async {
        expect(r.url.queryParameters, {'d': '2027-01-02', 's': 'Soccer'});
        return http.Response(
          jsonEncode({
            'events': [fixture(), fixture()],
          }),
          200,
        );
      });
      final rows = await p.getEventsByDate(
        DateTime(2027, 1, 2),
        sport: 'Soccer',
      );
      expect(rows.length, 1);
      expect(rows.single.startTimeUtc, DateTime.utc(2026, 11, 5, 20));
      p.dispose();
    },
  );
  test('upcoming and results use team and league endpoint contracts', () async {
    final paths = <String>[];
    final p = adapter((r) async {
      paths.add(r.url.path.split('/').last);
      return http.Response(
        jsonEncode({
          r.url.path.contains('eventslast') ? 'results' : 'events': [
            fixture(status: 'FT'),
          ],
        }),
        200,
      );
    });
    await p.getUpcomingEvents(leagueId: '4328');
    await p.getUpcomingEvents(teamId: '1');
    expect((await p.getRecentResults(teamId: '1')).length, 1);
    expect((await p.getRecentResults(leagueId: '4328')).length, 1);
    expect(paths, [
      'eventsnextleague.php',
      'eventsnext.php',
      'eventslast.php',
      'eventspastleague.php',
    ]);
    p.dispose();
  });
  for (final raw in ['{"events":null}', '{"events":[]}']) {
    test('null or empty fixtures: $raw', () async {
      final p = adapter((_) async => http.Response(raw, 200));
      expect(await p.getEventsByDate(DateTime(2026, 11, 5)), isEmpty);
      p.dispose();
    });
  }
  test('missing participants, scores, timestamps remain nullable', () {
    final e = TheSportsDbProvider.event({
      'idEvent': '1',
      'strEvent': 'Grand Prix',
    });
    expect(e.homeTeamName, isNull);
    expect(e.awayTeamName, isNull);
    expect(e.score, isNull);
    expect(e.startTimeUtc, isNull);
    expect(e.status, SportsEventStatus.unknown);
  });
  test('sport-specific score strings preserved', () {
    final e = TheSportsDbProvider.event({
      ...fixture(),
      'intHomeScore': '185/4 (18.3)',
      'intAwayScore': '180/8',
    });
    expect(e.homeScore, '185/4 (18.3)');
    expect(e.score, '185/4 (18.3) - 180/8');
  });
  test('statuses require explicit evidence, not clock or scores', () {
    for (final s in ['FT', 'AOT', 'AET', 'finished']) {
      expect(
        TheSportsDbProvider.status({'strStatus': s}),
        SportsEventStatus.finished,
      );
    }
    for (final s in ['1H', 'HT', 'Q3', 'In Progress']) {
      expect(
        TheSportsDbProvider.status({'strStatus': s}),
        SportsEventStatus.live,
      );
    }
    expect(
      TheSportsDbProvider.status({'strStatus': 'PST'}),
      SportsEventStatus.postponed,
    );
    expect(
      TheSportsDbProvider.status({'strStatus': 'CANC'}),
      SportsEventStatus.cancelled,
    );
    expect(
      TheSportsDbProvider.event({
        ...fixture(status: null),
        'intHomeScore': 2,
      }).status,
      SportsEventStatus.unknown,
    );
  });
  test('UTC offset parsing and local conversion preserve instant', () {
    expect(
      TheSportsDbProvider.utc('2026-11-05T20:00:00'),
      DateTime.utc(2026, 11, 5, 20),
    );
    final t = TheSportsDbProvider.utc('2026-11-05T16:30:00-03:30')!;
    expect(t, DateTime.utc(2026, 11, 5, 20));
    expect(t.toLocal().millisecondsSinceEpoch, t.millisecondsSinceEpoch);
  });
  test('429 stops retries and reserves at least a minute cooldown', () async {
    var calls = 0;
    final waits = <Duration>[];
    final p = adapter(
      (_) async {
        calls++;
        return http.Response('', 429);
      },
      wait: (d) async {
        waits.add(d);
      },
    );
    await expectLater(p.getSports(), throwsA(isA<SportsDataException>()));
    expect(calls, 1);
    await expectLater(p.getLeagues(), throwsA(isA<SportsDataException>()));
    expect(calls, 2);
    expect(waits.single.inSeconds, greaterThanOrEqualTo(59));
    p.dispose();
  });
  test('timeouts bounded to one retry', () async {
    var calls = 0;
    final p = adapter((_) async {
      calls++;
      throw TimeoutException('test');
    });
    await expectLater(p.getSports(), throwsA(isA<SportsDataException>()));
    expect(calls, 2);
    p.dispose();
  });
  test('malformed JSON fails without retries or leaking raw error', () async {
    var calls = 0;
    final p = adapter((_) async {
      calls++;
      return http.Response('{broken', 200);
    });
    await expectLater(
      p.getSports(),
      throwsA(
        isA<SportsDataException>().having(
          (e) => e.message,
          'message',
          'Unable to read sports information.',
        ),
      ),
    );
    expect(calls, 1);
    p.dispose();
  });
  test(
    'free coverage is marked limited and live does not perform requests',
    () async {
      var calls = 0;
      final p = adapter((_) async {
        calls++;
        return http.Response('{}', 200);
      });
      expect(p.limitedCoverage, isTrue);
      expect(p.supportsLive, isFalse);
      expect(await p.getLiveScores(), isEmpty);
      expect(calls, 0);
      p.dispose();
    },
  );
  test('free search rejects unrelated restricted response', () async {
    final p = adapter(
      (_) async =>
          http.Response('{"teams":[{"idTeam":"1","strTeam":"Arsenal"}]}', 200),
    );
    expect(await p.getTeams('Chelsea'), isEmpty);
    p.dispose();
  });
  test('metadata and detail lookups use normalized models', () async {
    final p = adapter(
      (r) async => http.Response(
        jsonEncode(
          r.url.path.contains('lookupevent')
              ? {
                  'events': [fixture()],
                }
              : r.url.path.contains('lookupleague')
              ? {
                  'leagues': [
                    {'idLeague': '3', 'strLeague': 'League'},
                  ],
                }
              : {
                  'teams': [
                    {'idTeam': '1', 'strTeam': 'Arsenal'},
                  ],
                },
        ),
        200,
      ),
    );
    expect((await p.getTeamDetails('1'))!.name, 'Arsenal');
    expect((await p.getLeagueDetails('3'))!.id, '3');
    expect((await p.getEventDetails('42'))!.id, '42');
    p.dispose();
  });
  test('paid keys and direct v2 config rejected', () {
    expect(
      () => const SportsApiConfig(key: 'paid-secret').base,
      throwsA(isA<SportsDataException>()),
    );
    expect(
      () => const SportsApiConfig(mode: 'premium_v2').base,
      throwsA(isA<SportsDataException>()),
    );
    expect(
      () => const SportsApiConfig(
        mode: 'backend',
        baseUrl: 'http://example.com',
      ).base,
      throwsA(isA<SportsDataException>()),
    );
  });
  test(
    'cache deduplicates requests and survives repository recreation offline',
    () async {
      var calls = 0;
      final gate = Completer<http.Response>();
      final p = adapter((_) async {
        calls++;
        return gate.future;
      });
      final a = p.getSports(), b = p.getSports();
      await Future<void>.delayed(Duration.zero);
      gate.complete(
        http.Response(
          '{"sports":[{"idSport":"102","strSport":"Soccer"}]}',
          200,
        ),
      );
      await Future.wait([a, b]);
      expect(calls, 1);
      p.dispose();
      final offline = adapter((_) async => throw Exception('offline'));
      expect((await offline.getSports()).single.name, 'Soccer');
      offline.dispose();
    },
  );
  test(
    'cache returns stale immediately then notifies on refreshed value',
    () async {
      var now = DateTime.utc(2026);
      final cache = SportsApiCache(now: () => now);
      await cache.get('x', const Duration(minutes: 1), () async => {'x': 1});
      now = now.add(const Duration(hours: 1));
      final gate = Completer<Map<String, dynamic>>();
      expect(
        await cache.get('x', const Duration(minutes: 1), () => gate.future),
        {'x': 1},
      );
      var changes = 0;
      cache.addListener(() => changes++);
      gate.complete({'x': 2});
      await Future<void>.delayed(Duration.zero);
      expect(await cache.get('x', const Duration(minutes: 1), () async => {}), {
        'x': 2,
      });
      expect(changes, 1);
      cache.dispose();
    },
  );
  test('teams and leagues persist independently per profile', () async {
    final a = SportsFavorites('a');
    await a.toggle('1', 'Team');
    await a.toggle('3', 'League', league: true);
    final restored = SportsFavorites('a');
    await restored.load();
    expect(restored.teams, {'1': 'Team'});
    expect(restored.leagues, {'3': 'League'});
    final other = SportsFavorites('b');
    await other.load();
    expect(other.teams, isEmpty);
    await restored.toggle('1', 'Team');
    await restored.toggle('3', 'League', league: true);
    final again = SportsFavorites('a');
    await again.load();
    expect(again.teams, isEmpty);
    expect(again.leagues, isEmpty);
  });
  test('concurrent favorites writes preserve both IDs', () async {
    final favorites = SportsFavorites('a');
    await favorites.load();
    // Toggle serialization is covered by concurrent, independent IDs.
    await Future.wait([
      favorites.toggle('1', 'One'),
      favorites.toggle('2', 'Two'),
    ]);
    expect(favorites.teams.length, 2);
  });
  final channel = ContentItem(
    id: 'provider-id-12',
    name: 'UK | SKY SPORTS HD',
    type: ContentType.live,
  );
  EpgProgramme epg(String title, {String description = '', int hour = 20}) =>
      EpgProgramme(
        title: title,
        description: description,
        start: DateTime.utc(2026, 11, 5, hour),
        end: DateTime.utc(2026, 11, 5, hour + 2),
      );
  test('verified EPG preserves original channel ID and object', () {
    final matches = SportsChannelMatcher().match(
      TheSportsDbProvider.event(fixture()),
      [channel],
      {
        channel.id: [epg('Premier League: Arsenal vs Chelsea')],
      },
    );
    expect(matches.single.confidence, SportsChannelConfidence.verified);
    expect(identical(matches.single.channel, channel), isTrue);
  });
  test('partial EPG evidence only possible; generic channels only related', () {
    final event = TheSportsDbProvider.event(fixture());
    expect(
      SportsChannelMatcher()
          .match(
            event,
            [channel],
            {
              channel.id: [epg('Arsenal vs Chelsea')],
            },
          )
          .single
          .confidence,
      SportsChannelConfidence.possible,
    );
    expect(
      SportsChannelMatcher().match(event, [channel], {}).single.confidence,
      SportsChannelConfidence.related,
    );
  });
  for (final title in [
    'Live Football',
    'Cricket Highlights',
    'Premier League Arsenal vs Chelsea Highlights',
  ]) {
    test('reject generic or replay EPG: $title', () {
      expect(
        SportsChannelMatcher()
            .match(
              TheSportsDbProvider.event(fixture()),
              [channel],
              {
                channel.id: [epg(title)],
              },
            )
            .single
            .confidence,
        SportsChannelConfidence.related,
      );
    });
  }
  test('wrong time and missing teams never verify', () {
    expect(
      SportsChannelMatcher()
          .match(
            TheSportsDbProvider.event(fixture()),
            [channel],
            {
              channel.id: [epg('Premier League Arsenal vs Chelsea', hour: 15)],
            },
          )
          .single
          .confidence,
      SportsChannelConfidence.related,
    );
  });
  test(
    'renamed channels retain provider IDs; absent channels not synthesized',
    () {
      final renamed = ContentItem(
        id: channel.id,
        name: 'New Name',
        type: ContentType.live,
      );
      final event = TheSportsDbProvider.event(fixture());
      expect(
        SportsChannelMatcher()
            .match(
              event,
              [renamed],
              {
                renamed.id: [epg('Premier League Arsenal vs Chelsea')],
              },
            )
            .single
            .channel
            .id,
        channel.id,
      );
      expect(SportsChannelMatcher().match(event, [], {}), isEmpty);
    },
  );
  test(
    'channel normalization removes quality without merging channel identity',
    () {
      expect(
        SportsChannelMatcher.normalize('UK | SKY SPORTS CRICKET HD'),
        'uk sky sports cricket',
      );
      expect(
        SportsChannelMatcher.sportsChannel('CRIC || WILLOW SPORTS FHD'),
        isTrue,
      );
      expect(SportsChannelMatcher.sportsChannel('ABC Movies HD'), isFalse);
    },
  );
  test('repository today filters dates and deduplicates union', () async {
    final p = adapter(
      (_) async => http.Response(
        jsonEncode({
          'events': [
            fixture(),
            fixture(),
            {...fixture(id: 'old'), 'strTimestamp': '2025-01-01T00:00:00'},
          ],
        }),
        200,
      ),
    );
    final rows = await SportsRepository(p).today(DateTime(2026, 11, 5));
    expect(rows.length, 1);
    p.dispose();
  });
}
