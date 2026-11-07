import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/sports.dart';
import 'sports_api_cache.dart';

class SportsApiConfig {
  final String mode, baseUrl, key;
  final bool liveScores, fullCoverage;
  const SportsApiConfig({
    this.liveScores = const bool.fromEnvironment('SPORTS_LIVE_SCORES'),
    this.fullCoverage = const bool.fromEnvironment('SPORTS_FULL_COVERAGE'),
    this.mode = const String.fromEnvironment(
      'SPORTS_API_MODE',
      defaultValue: 'free_v1',
    ),
    this.baseUrl = const String.fromEnvironment('SPORTS_API_BASE_URL'),
    this.key = const String.fromEnvironment(
      'SPORTS_API_KEY',
      defaultValue: '123',
    ),
  });
  Uri get base {
    if (mode != 'free_v1' && mode != 'backend') {
      throw const SportsDataException(
        'Configure a sports backend for premium data.',
      );
    }
    if (mode == 'free_v1' && key != '123') {
      throw const SportsDataException(
        'Paid sports keys must be kept on your backend.',
      );
    }
    final uri = Uri.tryParse(
      baseUrl.isEmpty && mode == 'free_v1'
          ? 'https://www.thesportsdb.com/api/v1/json/123/'
          : baseUrl,
    );
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const SportsDataException('Configure a secure sports API address.');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }
}

/// Normalizes v1 responses. A future backend can implement SportsDataProvider
/// directly, or expose this documented v1-compatible gateway contract.
class TheSportsDbProvider
    implements SportsDataProvider, SportsLeagueScheduleProvider {
  final SportsApiConfig config;
  final SportsApiCache cache;
  final http.Client client;
  final DateTime Function() now;
  final Future<void> Function(Duration) wait;
  final Duration timeout;
  static Future<void> _sharedTail = Future.value();
  static DateTime? _sharedNextRequest;
  Future<void> _localTail = Future.value();
  DateTime? _localNextRequest;
  final bool sharedLimits;
  Future<void> get _tail => sharedLimits ? _sharedTail : _localTail;
  set _tail(Future<void> value) {
    if (sharedLimits) {
      _sharedTail = value;
    } else {
      _localTail = value;
    }
  }

  DateTime? get _nextRequest =>
      sharedLimits ? _sharedNextRequest : _localNextRequest;
  set _nextRequest(DateTime? value) {
    if (sharedLimits) {
      _sharedNextRequest = value;
    } else {
      _localNextRequest = value;
    }
  }

  int _scheduleGeneration = 0;
  void cancelQueuedSchedules() {
    _scheduleGeneration++;
  }

  bool _closed = false;
  TheSportsDbProvider({
    this.config = const SportsApiConfig(),
    SportsApiCache? cache,
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
    this.timeout = const Duration(seconds: 15),
  }) : sharedLimits = client == null,
       cache = cache ?? SportsApiCache(),
       client = client ?? http.Client(),
       now = now ?? DateTime.now,
       wait = wait ?? Future<void>.delayed;
  @override
  bool get supportsLive => config.mode == 'backend' && config.liveScores;
  @override
  bool get limitedCoverage => config.mode != 'backend' || !config.fullCoverage;
  @override
  String get attribution => 'Sports data: TheSportsDB';

  Future<Map<String, dynamic>> _fetch(Uri uri, {bool Function()? valid}) {
    final task = _tail.then((_) async {
      if (_closed || valid?.call() == false) {
        throw const SportsRequestCancelled();
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final delay = _nextRequest?.difference(now()) ?? Duration.zero;
        if (delay > Duration.zero) await wait(delay);
        if (_closed || valid?.call() == false) {
          throw const SportsRequestCancelled();
        }
        // <=29 starts/minute, across all endpoints and retries in this adapter.
        _nextRequest = now().add(const Duration(milliseconds: 2100));
        try {
          final response = await client
              .get(uri, headers: {'Accept': 'application/json'})
              .timeout(timeout);
          if (response.statusCode == 429) {
            final seconds =
                int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
            _nextRequest = now().add(
              Duration(seconds: seconds < 60 ? 60 : seconds),
            );
            throw const SportsDataException(
              'Sports information is temporarily unavailable. Please try again shortly.',
            );
          }
          if (response.statusCode >= 500 && attempt == 0) {
            await wait(const Duration(seconds: 2));
            continue;
          }
          if (response.statusCode != 200) {
            throw const SportsDataException(
              'Unable to update sports information.',
            );
          }
          final raw = jsonDecode(response.body);
          if (raw is! Map<String, dynamic>) throw const FormatException();
          return raw;
        } on SportsDataException {
          rethrow;
        } on FormatException {
          throw const SportsDataException('Unable to read sports information.');
        } catch (_) {
          if (attempt == 0) {
            await wait(const Duration(seconds: 2));
            continue;
          }
          throw const SportsDataException(
            'Unable to update sports information.',
          );
        }
      }
      throw const SportsDataException('Unable to update sports information.');
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<List<Map<String, dynamic>>> _rows(
    String endpoint,
    String root, {
    Map<String, String> params = const {},
    Duration ttl = const Duration(hours: 24),
  }) async {
    final uri = config.base
        .resolve(endpoint)
        .replace(queryParameters: params.isEmpty ? null : params);
    final generation = _scheduleGeneration;
    final isSchedule = {
      'eventsday.php',
      'eventsnext.php',
      'eventsnextleague.php',
      'eventslast.php',
      'eventspastleague.php',
    }.contains(endpoint);
    Map<String, dynamic> data;
    try {
      data = endpoint == 'live_scores.php'
          ? await _fetch(uri)
          : await cache.get(
              uri.toString(),
              ttl,
              () => _fetch(
                uri,
                valid: isSchedule
                    ? () => generation == _scheduleGeneration
                    : null,
              ),
            );
    } on SportsRequestCancelled {
      // A renewed selection may have joined an obsolete in-flight cache entry.
      if (!_closed && generation == _scheduleGeneration) {
        return _rows(endpoint, root, params: params, ttl: ttl);
      }
      rethrow;
    }
    final rows = data[root];
    if (rows == null) return [];
    if (rows is! List) {
      throw const SportsDataException('Unable to read sports information.');
    }
    return rows
        .whereType<Map>()
        .map((x) => Map<String, dynamic>.from(x))
        .toList();
  }

  static String? text(dynamic value) {
    final s = value?.toString().trim();
    return s == null || s.isEmpty || s == 'null' ? null : s;
  }

  static DateTime? utc(String? value) {
    if (value == null) return null;
    final withZone =
        RegExp(r'(Z|[+-]\d\d:\d\d)$', caseSensitive: false).hasMatch(value)
        ? value
        : '${value}Z';
    return DateTime.tryParse(withZone)?.toUtc();
  }

  static SportsEventStatus status(Map<String, dynamic> row) {
    final s = text(row['strStatus'])?.toLowerCase();
    if (text(row['strPostponed'])?.toLowerCase() == 'yes' ||
        s == 'pst' ||
        s == 'postponed') {
      return SportsEventStatus.postponed;
    }
    if (['canc', 'cancelled', 'canceled'].contains(s)) {
      return SportsEventStatus.cancelled;
    }
    if ([
      'ft',
      'aet',
      'aot',
      'ap',
      'pen',
      'match finished',
      'finished',
    ].contains(s)) {
      return SportsEventStatus.finished;
    }
    if ([
      '1h',
      '2h',
      'ht',
      'et',
      'bt',
      'p',
      'live',
      'in progress',
      'q1',
      'q2',
      'q3',
      'q4',
      'ot',
      'in1',
      'in2',
    ].contains(s)) {
      return SportsEventStatus.live;
    }
    if (['ns', 'not started', 'scheduled'].contains(s)) {
      return SportsEventStatus.scheduled;
    }
    return SportsEventStatus.unknown;
  }

  static SportsEvent event(Map<String, dynamic> r) => SportsEvent(
    id: text(r['idEvent']) ?? '',
    name: text(r['strEvent']) ?? 'Event details unavailable',
    sportId: text(r['strSport']),
    leagueId: text(r['idLeague']),
    leagueName: text(r['strLeague']),
    homeTeamId: text(r['idHomeTeam']),
    awayTeamId: text(r['idAwayTeam']),
    homeTeamName: text(r['strHomeTeam']),
    awayTeamName: text(r['strAwayTeam']),
    homeTeamLogo: text(r['strHomeTeamBadge']),
    awayTeamLogo: text(r['strAwayTeamBadge']),
    startTimeUtc: utc(
      text(r['strTimestamp']) ??
          (text(r['dateEvent']) != null && text(r['strTime']) != null
              ? '${r['dateEvent']}T${r['strTime']}'
              : null),
    ),
    status: status(r),
    homeScore: text(r['intHomeScore']),
    awayScore: text(r['intAwayScore']),
    scoreDetail: text(r['strResult'])?.replaceAll(RegExp('<[^>]*>'), ' '),
    venue: text(r['strVenue']),
    round: text(r['intRound']),
    season: text(r['strSeason']),
    lastUpdated: utc(text(r['lastUpdated'])),
  );
  static SportsLeague league(Map<String, dynamic> r) => SportsLeague(
    text(r['idLeague']) ?? '',
    text(r['strLeague']) ?? 'Unnamed league',
    sportId: text(r['strSport']),
    country: text(r['strCountry']),
    logoUrl: text(r['strBadge']),
    currentSeason: text(r['strCurrentSeason']),
  );
  static SportsTeam team(Map<String, dynamic> r) => SportsTeam(
    text(r['idTeam']) ?? '',
    text(r['strTeam']) ?? 'Unnamed team',
    sportId: text(r['strSport']),
    leagueId: text(r['idLeague']),
    country: text(r['strCountry']),
    logoUrl: text(r['strBadge'] ?? r['strTeamBadge']),
  );
  Future<List<SportsEvent>> _events(
    String endpoint, {
    Map<String, String> params = const {},
    String root = 'events',
    Duration ttl = const Duration(minutes: 20),
  }) async {
    final rows = await _rows(endpoint, root, params: params, ttl: ttl);
    return {
      for (final r in rows)
        if (text(r['idEvent']) != null) r['idEvent'].toString(): event(r),
    }.values.toList();
  }

  @override
  Future<List<Sport>> getSports() async =>
      (await _rows('all_sports.php', 'sports'))
          .where(
            (r) => text(r['idSport']) != null && text(r['strSport']) != null,
          )
          .map(
            (r) => Sport(
              r['idSport'].toString(),
              r['strSport'].toString(),
              description: text(r['strSportDescription']),
              thumbnailUrl: text(r['strSportThumb']),
            ),
          )
          .toList();
  @override
  Future<List<SportsLeague>> getLeagues() async => (await _rows(
    'all_leagues.php',
    'leagues',
  )).map(league).where((x) => x.id.isNotEmpty).toList();
  @override
  Future<SportsLeague?> getLeagueDetails(String id) async => (await _rows(
    'lookupleague.php',
    'leagues',
    params: {'id': id},
  )).map(league).firstOrNull;
  @override
  Future<List<SportsEvent>> getEventsByDate(
    DateTime date, {
    String? sport,
  }) => _events(
    'eventsday.php',
    params: {
      'd':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      's': ?sport,
    },
  );
  @override
  Future<List<SportsEvent>> getLeagueEventsByDate(
    DateTime date,
    String leagueId,
  ) => _events(
    'eventsday.php',
    params: {
      'd':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'l': leagueId,
    },
  );
  @override
  Future<List<SportsEvent>> getUpcomingEvents({
    String? leagueId,
    String? teamId,
  }) => teamId == null && leagueId == null
      ? Future.value([])
      : _events(
          teamId != null ? 'eventsnext.php' : 'eventsnextleague.php',
          params: {'id': teamId ?? leagueId!},
          ttl: const Duration(hours: 2),
        );
  @override
  Future<List<SportsEvent>> getRecentResults({
    String? leagueId,
    String? teamId,
  }) async =>
      (await (teamId == null && leagueId == null
              ? Future.value(<SportsEvent>[])
              : _events(
                  teamId != null ? 'eventslast.php' : 'eventspastleague.php',
                  root: teamId != null ? 'results' : 'events',
                  params: {'id': teamId ?? leagueId!},
                  ttl: const Duration(minutes: 45),
                )))
          .where((e) => e.status == SportsEventStatus.finished)
          .toList();
  @override
  Future<List<SportsTeam>> getTeams(String query) async =>
      (await _rows('searchteams.php', 'teams', params: {'t': query.trim()}))
          .map(team)
          .where(
            (x) =>
                x.id.isNotEmpty &&
                x.name.toLowerCase().contains(query.trim().toLowerCase()),
          )
          .toList();
  @override
  Future<SportsTeam?> getTeamDetails(String id) async => (await _rows(
    'lookupteam.php',
    'teams',
    params: {'id': id},
  )).map(team).firstOrNull;
  @override
  Future<SportsEvent?> getEventDetails(String id) async =>
      (await _events('lookupevent.php', params: {'id': id})).firstOrNull;
  Future<List<SportsEvent>>? _liveRequest;
  @override
  Future<List<SportsEvent>> getLiveScores() {
    if (!supportsLive) return Future.value([]);
    return _liveRequest ??= () async {
      try {
        return await _events('live_scores.php', ttl: Duration.zero);
      } finally {
        _liveRequest = null;
      }
    }();
  }

  @override
  void dispose() {
    _closed = true;
    client.close();
    cache.dispose();
  }
}
