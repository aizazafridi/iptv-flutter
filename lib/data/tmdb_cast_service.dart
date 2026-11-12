import '../application/browsing_mode.dart';
import 'artwork_repository.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

class MovieCredit {
  final String name, role;
  final Uri? photo;
  const MovieCredit(this.name, this.role, [this.photo]);
  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'photo': photo?.toString(),
  };
  factory MovieCredit.fromJson(Map<String, dynamic> row) => MovieCredit(
    row['name'] as String,
    row['role'] as String,
    row['photo'] == null ? null : Uri.tryParse(row['photo'] as String),
  );
}

typedef TmdbFetch = Future<Map<String, dynamic>> Function(Uri uri);

/// Movie and series metadata only: IPTV credentials and stream URLs never leave the app.
class TmdbCastService {
  static final configured = TmdbCastService(
    token: const String.fromEnvironment(
      'TMDB_API_READ_TOKEN',
      defaultValue: String.fromEnvironment('TMDB_READ_ACCESS_TOKEN'),
    ),
    baseUrl: const String.fromEnvironment(
      'TMDB_API_BASE_URL',
      defaultValue: 'https://api.themoviedb.org/3',
    ),
  );
  final String token;
  final String baseUrl;
  final TmdbFetch? fetch;
  final bool persist;
  final _pending = <String, Future<List<MovieCredit>>>{};
  final _cache = <String, List<MovieCredit>>{};
  TmdbCastService({
    this.token = '',
    this.fetch,
    this.persist = true,
    this.baseUrl = 'https://api.themoviedb.org/3',
  });
  bool get enabled => token.isNotEmpty || fetch != null;
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u00c0-\uffff]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static String cleanTitle(String title) {
    var cleaned = title
        .replaceFirst(RegExp(r'[.\s|\-]+$'), '')
        .replaceAll(RegExp(r'^\s*[A-Z]{2,3}\s*[:|]\s*'), '');
    // Remove the whole quality wrapper, not just its contents: (4K) must
    // not become () and prevent a subsequent trailing-year match.
    cleaned = cleaned.replaceAll(
      RegExp(
        r'[\[(]\s*(?:4k|uhd|fhd|hd|1080p|720p|2160p|hdr|hevc|x265|x264)(?:[\s,/-]+(?:4k|uhd|fhd|hd|1080p|720p|2160p|hdr|hevc|x265|x264))*\s*[\])]',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned
        .replaceAll(
          RegExp(
            r'\b(?:4k|uhd|fhd|hd|1080p|720p|2160p)\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    cleaned = cleaned
        .replaceFirst(RegExp(r'[.\s|\-]+$'), '')
        .replaceAll(RegExp(r'\s*[\[(](?:19|20)\d{2}[\])]\s*$'), '')
        .trim();
    return cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceFirst(RegExp(r'[.\s|\-]+$'), '')
        .trim();
  }

  /// Provider language/dub labels describe a stream variant, not the TV title.
  static String cleanSeriesTitle(String title) {
    const languages =
        r'(?:english|hindi|urdu|tamil|telugu|malayalam|kannada|bengali|punjabi|spanish|arabic|korean|japanese|french|german|italian|portuguese|russian|chinese|turkish|dual audio|multi audio)';
    var value = title.trim();
    for (var i = 0; i < 3; i++) {
      value = value.replaceFirst(
        RegExp('^$languages\\s*[:|\\-]\\s*', caseSensitive: false),
        '',
      );
      value = value.replaceFirst(
        RegExp(
          '\\s*(?:[\\[(]\\s*$languages(?:\\s+dubbed)?\\s*[\\])]|(?:[-|:]\\s*|\\s+)$languages(?:\\s+dubbed)?)\\s*\$',
          caseSensitive: false,
        ),
        '',
      );
      value = cleanTitle(value);
    }
    return value;
  }

  String lookupTitle(MediaDetails info) => info.item.type == ContentType.series
      ? cleanSeriesTitle(info.item.name)
      : cleanTitle(info.item.name);

  String key(MediaDetails info) =>
      '${info.item.type == ContentType.series ? 'tv:' : ''}${info.tmdbId ?? ''}:${normalize(lookupTitle(info))}:${year(info)}';
  String? year(MediaDetails info) {
    final released = RegExp(
      r'\b(?:19|20)\d{2}\b',
    ).firstMatch(info.releaseDate)?.group(0);
    if (released != null) return released;
    // A year in the actual title (Wonder Woman 1984) is not a release year.
    return RegExp(
      r'[\[(]((?:19|20)\d{2})[\])]',
    ).allMatches(info.item.name).lastOrNull?.group(1);
  }

  Future<List<MovieCredit>> credits(MediaDetails info) {
    if (BrowsingModeSettings.instance.lite) return Future.value([]);
    if (!enabled) {
      debugPrint(
        'TMDB cast photos unavailable: start with --dart-define-from-file=config.dev.json to include the read token.',
      );
      return Future.value([]);
    }
    final id = info.item.type == ContentType.series
        ? 'credits:v2:${key(info)}'
        : key(info);
    if (_cache.containsKey(id)) {
      ArtworkMetrics.record(
        'metadata_cache',
        values: {'role': 'cast', 'source': 'memory'},
      );
      return Future.value(_cache[id]);
    }
    return _pending.putIfAbsent(
      id,
      () => _load(info, id).whenComplete(() {
        _pending.remove(id);
      }),
    );
  }

  Future<File> cacheFile(String key) async {
    var hash = 2166136261;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0xffffffff;
    }
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/tmdb_cast/${hash.toRadixString(16)}.json');
  }

  final _resolvedIds = <String, int>{};
  final _pendingIds = <String, Future<int?>>{};
  Future<int?> movieId(MediaDetails info) {
    final cacheKey = key(info);
    if (_resolvedIds.containsKey(cacheKey)) {
      return Future.value(_resolvedIds[cacheKey]);
    }
    return _pendingIds.putIfAbsent(
      cacheKey,
      () => _resolveId(info)
          .then((id) {
            if (id != null) _resolvedIds[cacheKey] = id;
            return id;
          })
          .whenComplete(() {
            _pendingIds.remove(cacheKey);
          }),
    );
  }

  Future<int?> _resolveId(MediaDetails info) async {
    var id = info.tmdbId;
    if (id != null && id <= 0) id = null;
    if (id == null) {
      final title = lookupTitle(info);
      if (title.isEmpty) return null;
      final tv = info.item.type == ContentType.series;
      Future<List<Map>> search({required bool useYear}) async {
        final results = await request(tv ? '/search/tv' : '/search/movie', {
          'query': title,
          'include_adult': 'false',
          if (useYear && year(info) != null)
            (tv ? 'first_air_date_year' : 'year'): year(info)!,
        });
        return (results['results'] as List? ?? []).whereType<Map>().where((
          row,
        ) {
          final matches =
              normalize('${row[tv ? 'name' : 'title'] ?? ''}') ==
                  normalize(title) ||
              normalize(
                    '${row[tv ? 'original_name' : 'original_title'] ?? ''}',
                  ) ==
                  normalize(title);
          return matches &&
              (!useYear ||
                  year(info) == null ||
                  '${row[tv ? 'first_air_date' : 'release_date'] ?? ''}'
                      .startsWith(year(info)!));
        }).toList();
      }

      var candidates = await search(useYear: true);
      if (tv && candidates.isEmpty && year(info) != null) {
        candidates = await search(useYear: false);
      }
      // Ambiguous matches keep provider names rather than showing the wrong cast.
      if (candidates.length != 1) return null;
      id = int.tryParse('${candidates.single['id']}');
    }
    return id != null && id > 0 ? id : null;
  }

  Future<List<MovieCredit>> _load(MediaDetails info, String key) async {
    if (persist) {
      try {
        final file = await cacheFile(key);
        final row =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (row['key'] == key &&
            DateTime.now().difference(DateTime.parse(row['saved'] as String)) <
                const Duration(days: 7)) {
          ArtworkMetrics.record(
            'metadata_cache',
            values: {'role': 'cast', 'source': 'disk'},
          );
          return _cache[key] = (row['credits'] as List)
              .map((c) => MovieCredit.fromJson(c as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {
        /* A missing cache never blocks the page. */
      }
    }
    try {
      final id = await movieId(info);
      if (id == null) return [];
      final kind = info.item.type == ContentType.series ? 'tv' : 'movie';
      Map<String, dynamic> data;
      if (kind == 'tv') {
        try {
          data = await request('/tv/$id/aggregate_credits');
        } catch (_) {
          data = await request('/tv/$id/credits');
        }
        if ((data['cast'] as List? ?? []).isEmpty) {
          data = await request('/tv/$id/credits');
        }
      } else {
        data = await request('/movie/$id/credits');
      }
      Uri? photo(dynamic path) {
        final value = path?.toString() ?? '';
        if (!RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(value)) return null;
        return Uri.https('image.tmdb.org', '/t/p/w185$value');
      }

      final cast = (data['cast'] as List? ?? []).whereType<Map>().toList()
        ..sort(
          (a, b) => ((a['order'] as num?) ?? 999).compareTo(
            (b['order'] as num?) ?? 999,
          ),
        );
      final people = [
        for (final row in cast.take(12))
          if ('${row['name'] ?? ''}'.trim().isNotEmpty)
            MovieCredit(
              '${row['name']}',
              row['character']?.toString() ??
                  ((row['roles'] as List? ?? [])
                          .whereType<Map>()
                          .firstOrNull?['character']
                          ?.toString() ??
                      'Cast'),
              photo(row['profile_path']),
            ),
        for (final row in (data['crew'] as List? ?? []).whereType<Map>())
          if (row['job'] == 'Director' &&
              '${row['name'] ?? ''}'.trim().isNotEmpty)
            MovieCredit(
              '${row['name']}',
              'Director',
              photo(row['profile_path']),
            ),
      ];
      if (people.isEmpty) return [];
      _cache[key] = people;
      if (persist) {
        try {
          final file = await cacheFile(key);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'key': key,
              'saved': DateTime.now().toIso8601String(),
              'credits': people.map((p) => p.toJson()).toList(),
            }),
          );
        } catch (_) {
          /* Read-only storage still permits in-memory caching. */
        }
      }
      return people;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final watch = Stopwatch()..start();
    final result = await ArtworkRepository.queue.run<Map<String, dynamic>>(
      'tmdb-http:${identityHashCode(this)}:${ArtworkMetrics.id('$path:${jsonEncode(query)}')}',
      () => requestData(path, query),
      priority: () => path.contains('credits')
          ? ArtworkPriority.cast
          : ArtworkPriority.visible,
      wanted: () => !BrowsingModeSettings.instance.lite,
    );
    ArtworkMetrics.record(
      'metadata_response',
      values: {
        'elapsed_ms': watch.elapsedMilliseconds,
        'category': path.contains('credits')
            ? 'cast'
            : path.contains('season')
            ? 'season'
            : path.contains('images')
            ? 'logos'
            : 'title',
      },
    );
    return result;
  }

  Future<Map<String, dynamic>> requestData(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final base = Uri.parse(baseUrl);
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty) {
      throw const FormatException('Invalid TMDB configuration');
    }
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}$path',
      queryParameters: query,
    );
    if (fetch != null) return fetch!(uri).timeout(const Duration(seconds: 8));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) {
        throw TmdbApiException(response.statusCode);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Metadata too large');
        }
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}

class TmdbApiException implements Exception {
  final int status;
  const TmdbApiException(this.status);
  String get message => switch (status) {
    401 || 403 =>
      'TMDB access is unavailable. Check the API token and restart Streamora.',
    429 => 'TMDB is receiving too many requests. Please try again shortly.',
    _ => 'TMDB is unavailable. Please try again later.',
  };
}
