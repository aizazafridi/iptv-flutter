import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../domain/live_score.dart';
import '../domain/sports.dart';
import '../application/sports_event_matcher.dart';

String? scoreText(dynamic value) =>
    value == null || value.toString().trim().isEmpty
    ? null
    : value.toString().trim();
DateTime? scoreUtc(dynamic value) {
  final text = scoreText(value);
  if (text == null) return null;
  return DateTime.tryParse(
    RegExp(r'(Z|[+-]\d\d:\d\d)$', caseSensitive: false).hasMatch(text)
        ? text
        : '${text}Z',
  )?.toUtc();
}

class ScoreApiFailure implements Exception {
  final String message;
  final int? code;
  const ScoreApiFailure(this.message, [this.code]);
}

abstract class CachedLiveScoreProvider implements LiveScoreProvider {
  final http.Client client;
  final FlutterSecureStorage storage;
  final DateTime Function() now;
  final int dailyBudget;
  final String credentialScope;
  bool closed = false;
  @override
  String? error;
  @override
  int requestCount = 0;
  @override
  DateTime? lastSuccess;
  DateTime? nextAttempt;
  int failures = 0, used = 0;
  String? usageDay;
  List<LiveScoreEvent> cached = [];
  Future<List<LiveScoreEvent>>? pending;
  CachedLiveScoreProvider({
    http.Client? client,
    this.storage = const FlutterSecureStorage(),
    DateTime Function()? now,
    required this.dailyBudget,
    this.credentialScope = '',
  }) : client = client ?? http.Client(),
       now = now ?? DateTime.now;
  Future<List<LiveScoreEvent>> fetchEvents();
  String get usageKey =>
      'sports_score_usage:$providerId:${sha256.convert(utf8.encode(credentialScope))}';
  Future<void> reserveRequest() async {
    final day = now().toUtc().toIso8601String().substring(0, 10);
    if (usageDay != day) {
      final saved = await storage.read(key: usageKey);
      final row = saved == null ? null : jsonDecode(saved) as Map;
      used = row?['day'] == day ? (row?['used'] as int? ?? 0) : 0;
      usageDay = day;
    }
    if (used >= dailyBudget) {
      throw const ScoreApiFailure('Daily score request budget reached.', 429);
    }
    used++;
    requestCount++;
    await storage.write(
      key: usageKey,
      value: jsonEncode({'day': day, 'used': used}),
    );
  }

  Future<dynamic> request(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    if (closed) throw const ScoreApiFailure('Score refresh cancelled.');
    await reserveRequest();
    final response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 429) {
      final delay = int.tryParse(response.headers['retry-after'] ?? '') ?? 120;
      nextAttempt = now().add(
        Duration(seconds: math.max(delay, refreshInterval.inSeconds)),
      );
      throw const ScoreApiFailure('Score request limit reached.', 429);
    }
    if (response.statusCode != 200) {
      throw ScoreApiFailure(
        [401, 403].contains(response.statusCode)
            ? 'Score provider key or plan is unavailable.'
            : 'Unable to refresh scores.',
        response.statusCode,
      );
    }
    return jsonDecode(response.body);
  }

  @override
  Future<List<LiveScoreEvent>> getLiveEvents() {
    if (closed || nextAttempt?.isAfter(now()) == true) {
      return Future.value(cached);
    }
    return pending ??= () async {
      try {
        final rows = await fetchEvents();
        cached = {
          for (final e in rows)
            if (e.providerEventId.isNotEmpty) e.providerEventId: e,
        }.values.toList();
        lastSuccess = now().toUtc();
        failures = 0;
        error = null;
        final regular = now().add(refreshInterval);
        if (nextAttempt == null || nextAttempt!.isBefore(regular)) {
          nextAttempt = regular;
        }
      } catch (e) {
        failures++;
        error = e is ScoreApiFailure ? e.message : 'Unable to refresh scores.';
        final wait = e is ScoreApiFailure && [401, 403].contains(e.code)
            ? const Duration(days: 1)
            : Duration(
                seconds: math.max(
                  refreshInterval.inSeconds,
                  math.min(1800, 30 * (1 << math.min(failures, 6))),
                ),
              );
        final retry = now().add(wait);
        if (nextAttempt == null || nextAttempt!.isBefore(retry)) {
          nextAttempt = retry;
        }
      } finally {
        pending = null;
      }
      return cached;
    }();
  }

  @override
  Future<LiveScoreEvent?> getEventScore(SportsEvent event) async {
    final matches = SportsEventMatcher().match([event], await getLiveEvents());
    return matches[event.id]?.$1;
  }

  @override
  void dispose() {
    closed = true;
    client.close();
  }
}

class CricketDataLiveScoreProvider extends CachedLiveScoreProvider {
  final String apiKey;
  final int activeDevices, intervalSeconds;
  int quotaIntervalSeconds = 0;
  CricketDataLiveScoreProvider({
    required this.apiKey,
    super.client,
    super.storage,
    super.now,
    super.dailyBudget = 75,
    this.activeDevices = 1,
    this.intervalSeconds = 300,
  }) : super(credentialScope: apiKey);
  @override
  String get providerId => 'cricketdata';
  @override
  Duration get refreshInterval => Duration(
    seconds: math.max(
      math.max(intervalSeconds, quotaIntervalSeconds),
      (86400 * math.max(1, activeDevices) / math.max(1, dailyBudget)).ceil(),
    ),
  );
  @override
  Future<List<LiveScoreEvent>> fetchEvents() async {
    final raw = await request(
      Uri.https('api.cricapi.com', '/v1/currentMatches', {
        'apikey': apiKey,
        'offset': '0',
      }),
    );
    if (raw is! Map || raw['status'] != 'success') {
      throw const ScoreApiFailure(
        'CricketData key, quota, or response is unavailable.',
        403,
      );
    }
    final info = raw['info'];
    if (info is Map && info['hitsToday'] is num && info['hitsLimit'] is num) {
      final remaining =
          (info['hitsLimit'] as num).toInt() -
          (info['hitsToday'] as num).toInt();
      if (remaining > 0) {
        final utc = now().toUtc();
        final seconds = DateTime.utc(
          utc.year,
          utc.month,
          utc.day + 1,
        ).difference(utc).inSeconds;
        quotaIntervalSeconds =
            (seconds * math.max(1, activeDevices) / remaining).ceil();
      }
    }
    if (info is Map &&
        info['hitsToday'] is num &&
        info['hitsLimit'] is num &&
        (info['hitsToday'] as num) >= (info['hitsLimit'] as num)) {
      nextAttempt = DateTime.utc(now().year, now().month, now().day + 1);
    }
    return parse(raw, now().toUtc(), refreshInterval);
  }

  static List<LiveScoreEvent> parse(Map raw, DateTime fetched, Duration ttl) {
    if (raw['data'] == null) return [];
    if (raw['data'] is! List) throw const FormatException();
    final result = <LiveScoreEvent>[];
    for (final r in (raw['data'] as List).whereType<Map>()) {
      final teams = (r['teams'] as List? ?? []).whereType<String>().toList();
      if (teams.length != 2 || scoreText(r['id']) == null) continue;
      final innings = (r['score'] as List? ?? []).whereType<Map>().toList();
      final aliases = <String, Set<int>>{};
      void alias(String name, int owner) => aliases
          .putIfAbsent(SportsEventMatcher.team(name), () => {})
          .add(owner);
      for (var i = 0; i < teams.length; i++) {
        alias(teams[i], i);
      }
      for (final info in (r['teamInfo'] as List? ?? []).whereType<Map>()) {
        final index = teams.indexWhere(
          (t) =>
              SportsEventMatcher.team(t) ==
              SportsEventMatcher.team(scoreText(info['name']) ?? ''),
        );
        if (index >= 0 && scoreText(info['shortname']) != null) {
          alias(info['shortname'].toString(), index);
        }
      }
      int? owner(String label) {
        final matches = aliases[SportsEventMatcher.team(label)];
        return matches?.length == 1 ? matches!.single : null;
      }

      String side(Map inning) => (scoreText(inning['inning']) ?? '')
          .replaceFirst(RegExp(r'\s+Innings?\b.*$', caseSensitive: false), '');
      String? number(Map inning) => RegExp(
        r'\bInnings?\s+(\d+)\b',
        caseSensitive: false,
      ).firstMatch(scoreText(inning['inning']) ?? '')?.group(1);
      final owners = innings.map((inning) => owner(side(inning))).toList();
      final explicit = List<int?>.from(owners);
      for (var i = 0; i < innings.length; i++) {
        if (owners[i] != null) continue;
        final parts = side(
          innings[i],
        ).split(',').map((s) => owner(s.trim())).toList();
        final inningNumber = number(innings[i]);
        if (parts.length != 2 ||
            parts.any((p) => p == null) ||
            parts.toSet().length != 2 ||
            inningNumber == null) {
          continue;
        }
        final peers = [
          for (var j = 0; j < innings.length; j++)
            if (number(innings[j]) == inningNumber) j,
        ];
        final known = peers
            .where((j) => explicit[j] != null)
            .map((j) => explicit[j]!)
            .toSet();
        // Recover a single malformed combined-team label only when the same
        // numbered innings already identifies exactly one team explicitly.
        // Multiple ambiguous rows or conflicting ownership stay unassigned.
        if (known.length == 1 &&
            peers.where((j) => explicit[j] == null).length == 1) {
          owners[i] = parts.cast<int>().firstWhere((p) => !known.contains(p));
        }
      }
      String? teamScore(String name) {
        final found = <String>[];
        final target = teams.indexOf(name);
        for (var index = 0; index < innings.length; index++) {
          final inning = innings[index];
          if (owners[index] != target || inning['r'] == null) continue;
          found.add(
            '${inning['r']}${inning['w'] == null ? '' : '/${inning['w']}'}${inning['o'] == null ? '' : ' (${inning['o']})'}',
          );
        }
        return found.isEmpty ? null : found.join(' / ');
      }

      String? logo(String team) {
        for (final info in (r['teamInfo'] as List? ?? []).whereType<Map>()) {
          if (SportsEventMatcher.team(scoreText(info['name']) ?? '') ==
              SportsEventMatcher.team(team)) {
            final image = scoreText(info['img']);
            final uri = Uri.tryParse(image ?? '');
            if (uri?.scheme == 'https') return image;
          }
        }
        return null;
      }

      final status = r['matchEnded'] == true
          ? SportsEventStatus.finished
          : r['matchStarted'] == true && r['matchEnded'] == false
          ? SportsEventStatus.live
          : SportsEventStatus.unknown;
      result.add(
        LiveScoreEvent(
          providerId: 'cricketdata',
          homeLogo: logo(teams[0]),
          awayLogo: logo(teams[1]),
          providerEventId: r['id'].toString(),
          sport: 'Cricket',
          homeTeamName: teams[0],
          awayTeamName: teams[1],
          leagueName: scoreText(r['seriesName']),
          leagueId: scoreText(r['series_id']),
          startTimeUtc: scoreUtc(r['dateTimeGMT']),
          lastUpdatedUtc: scoreUtc(r['lastUpdated']),
          fetchedAt: fetched,
          freshUntil: fetched.add(
            ttl > const Duration(minutes: 5) ? const Duration(minutes: 5) : ttl,
          ),
          status: status,
          homeScore: teamScore(teams[0]),
          awayScore: teamScore(teams[1]),
          detail: scoreText(r['status']),
          sportSpecificData: {'innings': innings, 'matchType': r['matchType']},
        ),
      );
    }
    return result;
  }
}

class BallDontLieLiveScoreProvider extends CachedLiveScoreProvider {
  final String apiKey;
  BallDontLieLiveScoreProvider({required this.apiKey, super.client, super.now})
    : super(dailyBudget: 720, credentialScope: apiKey);
  @override
  String get providerId => 'balldontlie';
  @override
  Duration get refreshInterval => const Duration(seconds: 120);
  @override
  Future<List<LiveScoreEvent>> fetchEvents() async {
    final utc = now().toUtc();
    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    final raw = await request(
      Uri.https('api.balldontlie.io', '/v1/games', {
        'dates[]': [date(utc.subtract(const Duration(days: 1))), date(utc)],
        'per_page': '100',
      }),
      headers: {'Authorization': apiKey},
    );
    if (raw is! Map) throw const FormatException();
    return parse(raw, utc, refreshInterval);
  }

  static List<LiveScoreEvent> parse(Map raw, DateTime fetched, Duration ttl) {
    if (raw['data'] == null) return [];
    if (raw['data'] is! List) throw const FormatException();
    final result = <LiveScoreEvent>[];
    for (final r in (raw['data'] as List).whereType<Map>()) {
      final home = r['home_team'], away = r['visitor_team'];
      if (home is! Map ||
          away is! Map ||
          scoreText(home['full_name']) == null ||
          scoreText(away['full_name']) == null ||
          r['id'] == null) {
        continue;
      }
      final status = scoreText(r['status_state'])?.toLowerCase();
      final legacy = scoreText(r['status'])?.toLowerCase() ?? '';
      final state = r['postponed'] == true
          ? SportsEventStatus.postponed
          : status == 'final' || legacy == 'final'
          ? SportsEventStatus.finished
          : ['in', 'live', 'in_progress'].contains(status) ||
                legacy.contains('qtr') ||
                legacy == 'halftime'
          ? SportsEventStatus.live
          : status == 'pre'
          ? SportsEventStatus.scheduled
          : SportsEventStatus.unknown;
      result.add(
        LiveScoreEvent(
          providerId: 'balldontlie',
          providerEventId: r['id'].toString(),
          sport: 'Basketball',
          leagueName: 'NBA',
          homeTeamName: home['full_name'],
          awayTeamName: away['full_name'],
          startTimeUtc: scoreUtc(r['datetime']),
          fetchedAt: fetched,
          freshUntil: fetched.add(
            ttl > const Duration(minutes: 5) ? const Duration(minutes: 5) : ttl,
          ),
          status: state,
          homeScore: scoreText(r['home_team_score']),
          awayScore: scoreText(r['visitor_team_score']),
          period: scoreText(r['period']),
          clock: scoreText(r['time']),
          lastUpdatedUtc: scoreUtc(r['updated_at']),
        ),
      );
    }
    return result;
  }
}

class OpenLigaDbLiveScoreProvider extends CachedLiveScoreProvider {
  final List<String> leagues;
  OpenLigaDbLiveScoreProvider({
    this.leagues = const ['bl1'],
    super.client,
    super.now,
  }) : super(dailyBudget: 500);
  @override
  String get providerId => 'openligadb';
  @override
  Duration get refreshInterval => const Duration(minutes: 5);
  @override
  Future<List<LiveScoreEvent>> fetchEvents() async {
    final events = <LiveScoreEvent>[];
    for (final league in leagues.where((l) => ['bl1', 'bl2'].contains(l))) {
      final raw = await request(
        Uri.https('api.openligadb.de', '/getmatchdata/$league'),
      );
      if (raw is! List) throw const FormatException();
      events.addAll(parse(raw, now().toUtc(), refreshInterval));
    }
    return events;
  }

  static List<LiveScoreEvent> parse(List raw, DateTime fetched, Duration ttl) {
    final result = <LiveScoreEvent>[];
    for (final r in raw.whereType<Map>()) {
      final h = r['team1'], a = r['team2'];
      if (h is! Map ||
          a is! Map ||
          scoreText(h['teamName']) == null ||
          scoreText(a['teamName']) == null ||
          r['matchID'] == null) {
        continue;
      }
      final scores = (r['matchResults'] as List? ?? [])
          .whereType<Map>()
          .where((s) => s['resultTypeID'] == 2)
          .toList();
      final score = scores.firstOrNull;
      result.add(
        LiveScoreEvent(
          providerId: 'openligadb',
          providerEventId: r['matchID'].toString(),
          sport: 'Soccer',
          leagueName: r['leagueShortcut'] == 'bl1'
              ? 'German Bundesliga'
              : r['leagueShortcut'] == 'bl2'
              ? 'German 2. Bundesliga'
              : null,
          homeTeamName: h['teamName'],
          awayTeamName: a['teamName'],
          startTimeUtc: scoreUtc(r['matchDateTimeUTC']),
          fetchedAt: fetched,
          freshUntil: fetched.add(
            ttl > const Duration(minutes: 5) ? const Duration(minutes: 5) : ttl,
          ),
          status: r['matchIsFinished'] == true
              ? SportsEventStatus.finished
              : SportsEventStatus.unknown,
          homeScore: scoreText(score?['pointsTeam1']),
          awayScore: scoreText(score?['pointsTeam2']),
        ),
      );
      // lastUpdateDateTime is a timezone-less local server string, not UTC.
    }
    return result;
  }
}
