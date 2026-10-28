import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import '../domain/models.dart';
import 'tmdb_cast_service.dart';

class MovieRatings {
  final String? imdb, rottenTomatoes;
  const MovieRatings({this.imdb, this.rottenTomatoes});
  bool get isEmpty => imdb == null && rottenTomatoes == null;
  Map<String, dynamic> toJson() => {
    'imdb': imdb,
    'rottenTomatoes': rottenTomatoes,
  };
  factory MovieRatings.fromJson(Map<String, dynamic> row) => MovieRatings(
    imdb: row['imdb'] as String?,
    rottenTomatoes: row['rottenTomatoes'] as String?,
  );
  factory MovieRatings.fromOmdb(Map<String, dynamic> row) {
    String? imdb;
    final value = double.tryParse('${row['imdbRating'] ?? ''}');
    if (value != null && value.isFinite && value >= 0 && value <= 10) {
      imdb = '${value.toStringAsFixed(1)}/10';
    }
    String? rotten;
    for (final rating in (row['Ratings'] as List? ?? []).whereType<Map>()) {
      if (rating['Source'] != 'Rotten Tomatoes') continue;
      final text = '${rating['Value'] ?? ''}';
      if (!RegExp(r'^\d{1,3}%$').hasMatch(text)) continue;
      final number = int.parse(text.replaceAll('%', ''));
      if (number <= 100) rotten = '$number%';
    }
    return MovieRatings(imdb: imdb, rottenTomatoes: rotten);
  }
}

class OmdbRatingsService {
  static final configured = OmdbRatingsService(
    apiKey: const String.fromEnvironment('OMDB_API_KEY'),
  );
  final String apiKey;
  final TmdbFetch? fetch;
  final bool persist;
  final TmdbCastService? metadataClient;
  final _cache = <String, MovieRatings>{};
  final _pending = <String, Future<MovieRatings>>{};
  OmdbRatingsService({
    this.apiKey = '',
    this.fetch,
    this.persist = true,
    this.metadataClient,
  });
  bool get enabled => apiKey.isNotEmpty || fetch != null;
  Future<MovieRatings> ratings(MediaDetails info) {
    if (!enabled) {
      debugPrint(
        'OMDb ratings unavailable: OMDB_API_KEY was not included at app launch. Fully restart using the development configuration.',
      );
      return Future.value(const MovieRatings());
    }
    final key =
        'ratings:${info.item.type == ContentType.series ? 'tv-v1' : 'v3'}:${info.imdbId ?? ''}:${TmdbCastService.configured.key(info)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _pending.putIfAbsent(
      key,
      () => _load(info, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<MovieRatings> _load(MediaDetails info, String key) async {
    if (persist) {
      try {
        final row =
            jsonDecode(
                  await (await TmdbCastService.configured.cacheFile(
                    key,
                  )).readAsString(),
                )
                as Map<String, dynamic>;
        if (row['key'] == key &&
            DateTime.now().difference(DateTime.parse(row['saved'] as String)) <
                const Duration(days: 7)) {
          return _cache[key] = MovieRatings.fromJson(
            row['ratings'] as Map<String, dynamic>,
          );
        }
      } catch (_) {
        /* Missing cache is normal for a new title. */
      }
    }
    try {
      var id = info.imdbId;
      if (id == null || !RegExp(r'^tt\d{7,10}$').hasMatch(id)) {
        id = null;
        final metadata = metadataClient ?? TmdbCastService.configured;
        if (metadata.enabled &&
            (info.item.type == ContentType.series ||
                (info.tmdbId != null && info.tmdbId! > 0))) {
          try {
            final tv = info.item.type == ContentType.series;
            final tmdbId = tv ? await metadata.movieId(info) : info.tmdbId;
            final movie = tmdbId == null
                ? <String, dynamic>{}
                : await metadata.request(
                    tv ? '/tv/$tmdbId/external_ids' : '/movie/$tmdbId',
                  );
            final resolved = movie['imdb_id']?.toString();
            if (resolved != null &&
                RegExp(r'^tt\d{7,10}$').hasMatch(resolved)) {
              id = resolved;
            }
          } catch (_) {
            /* Title/year lookup remains available. */
          }
        }
      }
      final title = info.item.type == ContentType.series
          ? TmdbCastService.cleanSeriesTitle(info.item.name)
          : TmdbCastService.cleanTitle(info.item.name);
      final year = TmdbCastService.configured.year(info);
      final byId = id != null && RegExp(r'^tt\d{7,10}$').hasMatch(id);
      final uri = Uri.https('www.omdbapi.com', '/', {
        'apikey': apiKey,
        'type': info.item.type == ContentType.series ? 'series' : 'movie',
        if (byId) 'i': id else 't': title,
        if (!byId && year != null) 'y': year,
      });
      final row = await (fetch == null ? request(uri) : fetch!(uri)).timeout(
        const Duration(seconds: 10),
      );
      if (row['Response'] != 'True') {
        final reason = switch (row['Error']) {
          'Invalid API key!' => 'key rejected',
          'Request limit reached!' => 'daily request limit reached',
          'Movie not found!' => 'movie title not found',
          _ => 'ratings unavailable',
        };
        debugPrint('OMDb ratings: $reason.');
        return const MovieRatings();
      }
      if (byId) {
        if (row['imdbID'] != id) return const MovieRatings();
      } else {
        final expected = TmdbCastService.normalize(title);
        final actual = TmdbCastService.normalize('${row['Title'] ?? ''}');
        String withoutArticle(String text) =>
            text.replaceFirst(RegExp(r'^(?:the|a|an) '), '');
        final sameYear =
            year == null ||
            (info.item.type == ContentType.series
                ? '${row['Year'] ?? ''}'.startsWith(year)
                : '${row['Year'] ?? ''}' == year);
        final sameTitle =
            actual == expected ||
            (year != null &&
                withoutArticle(actual) == withoutArticle(expected));
        if (!sameTitle || !sameYear) {
          debugPrint(
            'OMDb ratings skipped: title or release year did not match.',
          );
          return const MovieRatings();
        }
      }
      final result = MovieRatings.fromOmdb(row);
      _cache[key] = result;
      if (_cache.length > 200) _cache.remove(_cache.keys.first);
      if (persist) {
        try {
          final file = await TmdbCastService.configured.cacheFile(key);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'key': key,
              'saved': DateTime.now().toIso8601String(),
              'ratings': result.toJson(),
            }),
          );
        } catch (_) {
          /* Still keep the in-memory cache. */
        }
      }
      return result;
    } catch (_) {
      // Network exceptions may contain the API key: never log their text.
      return const MovieRatings();
    }
  }

  Future<Map<String, dynamic>> request(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw const FormatException('Ratings unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) {
          throw const FormatException('Ratings too large');
        }
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }
}
