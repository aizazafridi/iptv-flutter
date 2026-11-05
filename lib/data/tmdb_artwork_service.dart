import 'artwork_repository.dart';
import '../application/browsing_mode.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/models.dart';
import 'tmdb_cast_service.dart';

/// Shared, non-blocking lookup. Only constructed Continue Watching cards call it.
class TmdbArtworkService {
  static final configured = TmdbArtworkService(
    client: TmdbCastService.configured,
  );
  final TmdbCastService client;
  final bool persist;
  final _cache = <String, Uri>{};
  final _pending = <String, Future<Uri?>>{};
  TmdbArtworkService({required this.client, this.persist = true});
  final _seasonStills = <String, Future<Map<int, Uri>>>{};
  Future<Uri?> episodeStill(MediaDetails info, Episode episode) async {
    if (BrowsingModeSettings.instance.lite ||
        !client.enabled ||
        info.item.type != ContentType.series) {
      return null;
    }
    final key = 'season-stills:v1:${client.key(info)}:${episode.season}';
    final stills = await _seasonStills.putIfAbsent(
      key,
      () => _loadSeasonStills(info, episode.season, key),
    );
    return stills[episode.number];
  }

  Future<Map<int, Uri>> _loadSeasonStills(
    MediaDetails info,
    int season,
    String key,
  ) async {
    if (persist) {
      try {
        final row =
            jsonDecode(await (await client.cacheFile(key)).readAsString())
                as Map<String, dynamic>;
        if (row['key'] == key &&
            DateTime.now().difference(DateTime.parse(row['saved'] as String)) <
                const Duration(days: 7)) {
          return (row['stills'] as Map<String, dynamic>).map(
            (number, path) =>
                MapEntry(int.parse(number), Uri.parse(path as String)),
          );
        }
      } catch (_) {
        /* Missing season metadata is normal. */
      }
    }
    try {
      final id = await client.movieId(info);
      if (id == null) return {};
      final data = await client.request('/tv/$id/season/$season');
      final stills = <int, Uri>{};
      for (final row in (data['episodes'] as List? ?? []).whereType<Map>()) {
        final number = int.tryParse('${row['episode_number']}');
        final path = '${row['still_path'] ?? ''}';
        if (number != null && RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(path)) {
          stills[number] = Uri.https('image.tmdb.org', '/t/p/w500$path');
        }
      }
      if (persist && stills.isNotEmpty) {
        try {
          final file = await client.cacheFile(key);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'key': key,
              'saved': DateTime.now().toIso8601String(),
              'stills': stills.map(
                (number, uri) => MapEntry('$number', uri.toString()),
              ),
            }),
          );
        } catch (_) {
          /* Artwork remains available without disk caching. */
        }
      }
      return stills;
    } catch (_) {
      return {};
    }
  }

  Future<Uri?> titleLogo(MediaDetails info) {
    if (BrowsingModeSettings.instance.lite || !client.enabled) {
      return Future.value(null);
    }
    final key = 'logo:v1:${client.key(info)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _pending.putIfAbsent(
      key,
      () => _loadLogo(info, key).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<Uri?> _loadLogo(MediaDetails info, String key) async {
    if (persist) {
      try {
        final row =
            jsonDecode(await (await client.cacheFile(key)).readAsString())
                as Map<String, dynamic>;
        if (row['key'] == key &&
            DateTime.now().difference(DateTime.parse(row['saved'] as String)) <
                const Duration(days: 7)) {
          final uri = Uri.parse(row['logo'] as String);
          if (uri.scheme == 'https' && uri.host == 'image.tmdb.org') {
            return _cache[key] = uri;
          }
        }
      } catch (_) {
        /* Missing logo cache is normal. */
      }
    }
    try {
      final id = await client.movieId(info);
      if (id == null) return null;
      final kind = info.item.type == ContentType.series ? 'tv' : 'movie';
      final data = await client.request('/$kind/$id/images', {
        'include_image_language': 'en,null',
      });
      final logos = (data['logos'] as List? ?? [])
          .whereType<Map>()
          .where(
            (row) =>
                (row['iso_639_1'] == 'en' || row['iso_639_1'] == null) &&
                RegExp(
                  r'^/[a-zA-Z0-9._-]+$',
                ).hasMatch('${row['file_path'] ?? ''}'),
          )
          .toList();
      logos.sort((a, b) {
        final language = (a['iso_639_1'] == 'en' ? 0 : 1).compareTo(
          b['iso_639_1'] == 'en' ? 0 : 1,
        );
        if (language != 0) return language;
        final votes = ((b['vote_average'] as num?) ?? 0).compareTo(
          (a['vote_average'] as num?) ?? 0,
        );
        return votes != 0
            ? votes
            : ((b['width'] as num?) ?? 0).compareTo((a['width'] as num?) ?? 0);
      });
      if (logos.isEmpty) return null;
      final path = '${logos.first['file_path']}'.replaceFirst(
        RegExp(r'\.svg$'),
        '.png',
      );
      final uri = Uri.https('image.tmdb.org', '/t/p/w500$path');
      _cache[key] = uri;
      if (persist) {
        try {
          final file = await client.cacheFile(key);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'key': key,
              'saved': DateTime.now().toIso8601String(),
              'logo': uri.toString(),
            }),
          );
        } catch (_) {
          /* Keep the in-memory logo when disk caching is unavailable. */
        }
      }
      return uri;
    } catch (_) {
      return null;
    }
  }

  /// Details pages already have provider metadata/IDs; avoid a second name-only search.
  Future<Uri?> detailsBackdrop(MediaDetails info) =>
      _detailsArtwork(info, 'backdrop_path');
  Future<Uri?> detailsPoster(MediaDetails info) =>
      _detailsArtwork(info, 'poster_path');
  Future<Uri?> _detailsArtwork(MediaDetails info, String field) {
    if (BrowsingModeSettings.instance.lite || !client.enabled) {
      return Future.value(null);
    }
    final key = 'details-$field:v1:${client.key(info)}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _pending.putIfAbsent(
      key,
      () => _detailsBackdrop(info, key, field).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<Uri?> _detailsBackdrop(
    MediaDetails info,
    String key,
    String field,
  ) async {
    try {
      final id = await client.movieId(info);
      if (id == null) return null;
      final kind = info.item.type == ContentType.series ? 'tv' : 'movie';
      final data = await client.request('/$kind/$id');
      final path = '${data[field] ?? ''}';
      if (!RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(path)) return null;
      return _cache[key] = Uri.https(
        'image.tmdb.org',
        '/t/p/${field == 'poster_path' ? 'w342' : 'w1280'}$path',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uri?> measureLookup(
    String role,
    Future<Uri?> Function() lookup,
  ) async {
    final watch = Stopwatch()..start();
    final uri = await lookup();
    ArtworkMetrics.record(
      'artwork_metadata_ready',
      url: uri?.toString(),
      values: {
        'role': role,
        'elapsed_ms': watch.elapsedMilliseconds,
        'found': uri != null,
      },
    );
    return uri;
  }

  Future<Uri?> backdrop(ContentItem item) =>
      measureLookup('backdrop', () => _catalogArtwork(item, false));
  Future<Uri?> poster(ContentItem item) =>
      measureLookup('poster', () => _catalogArtwork(item, true));

  /// Reads known artwork URLs without starting a TMDB network search.
  Future<Uri?> cachedPoster(ContentItem item) =>
      _catalogArtwork(item, true, cacheOnly: true);

  Future<Uri?> _catalogArtwork(
    ContentItem item,
    bool poster, {
    bool cacheOnly = false,
  }) {
    if (BrowsingModeSettings.instance.lite ||
        !client.enabled ||
        item.type == ContentType.live) {
      return Future.value(null);
    }
    final title = item.type == ContentType.series
        ? TmdbCastService.cleanSeriesTitle(item.name)
        : TmdbCastService.cleanTitle(item.name);
    final info = MediaDetails(item: item, synopsis: '');
    final kind = item.type == ContentType.series ? 'tv' : 'movie';
    final year = client.year(info);
    final key =
        '${poster ? 'poster' : 'backdrop'}:$kind:${TmdbCastService.normalize(title)}:$year';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    if (cacheOnly) {
      return _load(kind, title, year, key, 'poster_path', cacheOnly: true);
    }
    return _pending.putIfAbsent(
      key,
      () =>
          _load(
            kind,
            title,
            year,
            key,
            poster ? 'poster_path' : 'backdrop_path',
          ).whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  Future<Uri?> _load(
    String kind,
    String title,
    String? year,
    String key,
    String field, {
    bool cacheOnly = false,
  }) async {
    if (persist) {
      try {
        final row =
            jsonDecode(await (await client.cacheFile(key)).readAsString())
                as Map<String, dynamic>;
        if (row['key'] == key &&
            DateTime.now().difference(DateTime.parse(row['saved'] as String)) <
                const Duration(days: 7)) {
          final uri = Uri.parse(row['backdrop'] as String);
          if (uri.scheme == 'https' && uri.host == 'image.tmdb.org') {
            return _cache[key] = uri;
          }
        }
      } catch (_) {
        /* Fetch when a valid cache is unavailable. */
      }
    }
    if (cacheOnly) return null;
    try {
      final results = await client.request('/search/$kind', {
        'query': title,
        'include_adult': 'false',
        (kind == 'tv' ? 'first_air_date_year' : 'year'): ?year,
      });
      final candidates = (results['results'] as List? ?? [])
          .whereType<Map>()
          .where((row) {
            final names = kind == 'tv'
                ? [row['name'], row['original_name']]
                : [row['title'], row['original_title']];
            return names.any(
                  (name) =>
                      name != null &&
                      TmdbCastService.normalize('$name') ==
                          TmdbCastService.normalize(title),
                ) &&
                (year == null ||
                    '${row[kind == 'tv' ? 'first_air_date' : 'release_date'] ?? ''}'
                        .startsWith(year));
          })
          .toList();
      if (candidates.length != 1) return null;
      var path = candidates.single[field]?.toString();
      if (path == null || path.isEmpty) {
        final id = int.tryParse('${candidates.single['id']}');
        if (id == null) return null;
        final details = await client.request('/$kind/$id');
        path = details[field]?.toString();
      }
      if (path == null || !RegExp(r'^/[a-zA-Z0-9._-]+$').hasMatch(path)) {
        return null;
      }
      final uri = Uri.https(
        'image.tmdb.org',
        '/t/p/${field == 'poster_path' ? 'w342' : 'w780'}$path',
      );
      _cache[key] = uri;
      if (_cache.length > 200) _cache.remove(_cache.keys.first);
      if (persist) {
        try {
          final file = await client.cacheFile(key);
          await file.parent.create(recursive: true);
          await file.writeAsString(
            jsonEncode({
              'key': key,
              'saved': DateTime.now().toIso8601String(),
              'backdrop': uri.toString(),
            }),
          );
        } catch (_) {
          /* Memory caching still works without writable storage. */
        }
      }
      return uri;
    } catch (_) {
      debugPrint('TMDB backdrop unavailable; using the full poster.');
      return null;
    }
  }
}
