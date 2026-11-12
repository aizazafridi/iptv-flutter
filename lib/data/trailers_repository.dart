import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/trailer_movie.dart';
import 'tmdb_cast_service.dart';
import 'artwork_repository.dart';
import 'bounded_cache.dart';

enum TrailerCollection { upcoming, upcomingBollywood, popular, nowPlaying }

extension TrailerCollectionLabel on TrailerCollection {
  String get label => switch (this) {
    TrailerCollection.upcoming => 'Upcoming Hollywood Releases',
    TrailerCollection.upcomingBollywood => 'Upcoming Bollywood Releases',
    TrailerCollection.popular => 'Popular Trailers',
    TrailerCollection.nowPlaying => 'Now in Theaters',
  };
  String get path => switch (this) {
    TrailerCollection.upcoming => 'upcoming',
    TrailerCollection.upcomingBollywood => 'upcoming',
    TrailerCollection.popular => 'popular',
    TrailerCollection.nowPlaying => 'now_playing',
  };
}

class TrailerDiscoveryError implements Exception {
  final String message;
  const TrailerDiscoveryError(this.message);
}

class TrailersRepository {
  // Metadata must not wait for slow poster/backdrop body downloads.
  static final _metadataQueue = ArtworkQueue(
    foregroundLimit: 2,
    backgroundLimit: 1,
  );
  static final configured = TrailersRepository(
    client: TmdbCastService.configured,
  );
  final TmdbCastService client;
  final String configuredLanguage, configuredRegion;
  final bool persist;
  final Duration timeout;
  final DateTime Function() clock;
  TrailersRepository({
    required this.client,
    this.configuredLanguage = const String.fromEnvironment('TMDB_LANGUAGE'),
    this.configuredRegion = const String.fromEnvironment('TMDB_REGION'),
    this.persist = true,
    this.timeout = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  String language = 'en-US', region = 'US';
  void locale(String languageTag, String? country) {
    language = configuredLanguage.isNotEmpty ? configuredLanguage : languageTag;
    region = configuredRegion.isNotEmpty
        ? configuredRegion
        : (country?.isNotEmpty == true ? country! : 'US');
  }

  final _cache =
      BoundedCache<String, ({Map<String, dynamic> data, DateTime saved})>(64);
  final _pending =
      <String, Future<({Map<String, dynamic> data, bool stale})>>{};
  Future<({Map<String, dynamic> data, bool stale})> _get(
    String path,
    Map<String, String> query, {
    bool background = false,
    bool refresh = false,
  }) {
    final key =
        'trailers:v1:${client.baseUrl}:$language:$region:$path:${jsonEncode(query)}';
    return _pending.putIfAbsent(
      key,
      () => Future<({Map<String, dynamic> data, bool stale})>(() async {
        try {
          var previous = _cache[key];
          File? file;
          if (previous == null && persist) {
            try {
              file = await client.cacheFile(key);
              final json =
                  jsonDecode(await file.readAsString()) as Map<String, dynamic>;
              if (json['key'] == key) {
                previous = (
                  data: json['data'] as Map<String, dynamic>,
                  saved: DateTime.parse(json['saved']),
                );
                _cache[key] = previous;
              }
            } catch (_) {
              /* No cached data yet. */
            }
          }
          if (!refresh &&
              previous != null &&
              clock().difference(previous.saved) < const Duration(hours: 6)) {
            return (data: previous.data, stale: false);
          }
          try {
            if (!client.enabled) {
              throw const TrailerDiscoveryError(
                'TMDB is not configured. Restart with your TMDB API token.',
              );
            }
            final data = await _metadataQueue.run<Map<String, dynamic>>(
              'trailer-metadata:${identityHashCode(this)}:${ArtworkMetrics.id(key)}',
              () => client.requestData(path, query).timeout(timeout),
              priority: () => background
                  ? ArtworkPriority.nearVisible
                  : ArtworkPriority.visible,
              wanted: () => true,
            ); // Metadata remains available in Lite Mode; images do not.
            _cache[key] = (data: data, saved: clock());
            if (persist) {
              try {
                file ??= await client.cacheFile(key);
                await file.parent.create(recursive: true);
                await file.writeAsString(
                  jsonEncode({
                    'key': key,
                    'saved': clock().toIso8601String(),
                    'data': data,
                  }),
                );
              } catch (_) {
                /* Disk cache is optional; usable metadata is ready. */
              }
            }
            return (data: data, stale: false);
          } catch (e) {
            if (previous != null) return (data: previous.data, stale: true);
            throw TrailerDiscoveryError(
              e is TrailerDiscoveryError
                  ? e.message
                  : e is TmdbApiException
                  ? e.message
                  : 'Movie discovery could not be loaded. Check your connection and try again.',
            );
          }
        } finally {
          _pending.remove(key);
        }
      }),
    );
  }

  Future<TrailerPage> page(
    TrailerCollection collection, {
    int page = 1,
    bool refresh = false,
  }) async {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    final bollywood = collection == TrailerCollection.upcomingBollywood;
    final upcoming = collection == TrailerCollection.upcoming || bollywood;
    final tomorrow = DateTime(
      today.year,
      today.month,
      today.day + 1,
    ).toIso8601String().substring(0, 10);
    final response = await _get(
      upcoming ? '/discover/movie' : '/movie/${collection.path}',
      {
        'language': language,
        if (!upcoming) 'region': region,
        'page': '$page',
        if (upcoming) ...{
          // Original release dates exclude regional re-releases.
          // English-language US productions approximate Hollywood releases.
          'primary_release_date.gte': tomorrow,
          'with_original_language': bollywood ? 'hi' : 'en',
          'with_origin_country': bollywood ? 'IN' : 'US',
          'include_adult': 'false',
          'include_video': 'false',
          'sort_by': 'primary_release_date.asc',
        },
      },
      refresh: refresh,
    );
    final rows = (response.data['results'] as List? ?? [])
        .whereType<Map>()
        .where((r) => r['adult'] != true && r['id'] is num)
        .map(
          (r) => TrailerMovie.fromJson(
            Map<String, dynamic>.from(r),
            region: region,
          ),
        )
        .where(
          (movie) =>
              !upcoming ||
              (movie.release != null &&
                  DateTime(
                    movie.release!.year,
                    movie.release!.month,
                    movie.release!.day,
                  ).isAfter(today)),
        )
        .toList();
    if (upcoming) {
      rows.sort((a, b) {
        final result = a.release!.compareTo(b.release!);
        return result == 0 ? a.id.compareTo(b.id) : result;
      });
    }
    final movies = <TrailerMovie>[];
    if (collection == TrailerCollection.popular) {
      // Validate only this requested page, in small batches, using cached videos
      // rather than downloading full details or artwork for every result.
      for (var i = 0; i < rows.length; i += 4) {
        final batch = rows.skip(i).take(4).toList();
        var failures = 0;
        TrailerDiscoveryError? firstError;
        final videos = await Future.wait(
          batch.map((m) async {
            try {
              return await video(
                m.id,
                background: true,
                preferredLanguage: m.originalLanguage == 'hi' ? 'hi-IN' : null,
              );
            } catch (e) {
              failures++;
              firstError ??= e is TrailerDiscoveryError
                  ? e
                  : const TrailerDiscoveryError(
                      'Trailer metadata is temporarily unavailable.',
                    );
              return null;
            }
          }),
        );
        if (failures == batch.length) {
          if (movies.isEmpty) {
            throw firstError!;
          }
          break; // Return usable results without hammering an unavailable API.
        }
        for (var j = 0; j < batch.length; j++) {
          if (videos[j] != null) movies.add(batch[j].withVideo(videos[j]));
        }
      }
    } else {
      movies.addAll(rows);
    }
    return TrailerPage(
      movies,
      (response.data['page'] as num?)?.toInt() ?? page,
      ((response.data['total_pages'] as num?)?.toInt() ?? 1).clamp(1, 500),
      stale: response.stale,
    );
  }

  Future<TrailerVideo?> video(
    int id, {
    bool background = false,
    String? preferredLanguage,
  }) async {
    final result = await _get('/movie/$id/videos', {
      'language': preferredLanguage ?? language,
    }, background: background);
    return TrailerVideo.select(result.data['results'] as List? ?? []);
  }

  Future<TrailerMovie> details(int id, {bool refresh = false}) async {
    final response = await _get('/movie/$id', {
      'language': language,
      'append_to_response': 'videos,release_dates,credits',
    }, refresh: refresh);
    final movie = TrailerMovie.fromJson(response.data, region: region);
    if (response.data['adult'] == true) {
      throw const TrailerDiscoveryError(
        'This movie is unavailable in discovery.',
      );
    }
    if (movie.video != null) return movie;
    try {
      return movie.withVideo(
        await video(
          id,
          preferredLanguage: movie.originalLanguage == 'hi' ? 'hi-IN' : null,
        ),
      );
    } catch (_) {
      // Optional localized video lookup must not discard loaded cast/details.
      return movie;
    }
  }
}
