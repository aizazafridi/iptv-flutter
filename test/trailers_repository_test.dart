import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/artwork_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/data/trailers_repository.dart';
import 'package:iptv_flutter/domain/trailer_movie.dart';
import 'package:iptv_flutter/application/trailer_reminders.dart';
import 'package:iptv_flutter/application/trailer_catalog_match.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'widget_test.dart' show FakeProvider;

Map<String, dynamic> movieJson(int id) => {
  'id': id,
  'title': 'Movie $id',
  'original_title': 'Movie $id',
  'overview': 'A movie synopsis',
  'release_date': '2027-04-10',
  'poster_path': '/poster.jpg',
  'backdrop_path': '/backdrop.jpg',
  'adult': false,
};
Map<String, dynamic> videoJson(
  String key, {
  String type = 'Trailer',
  bool official = true,
  String site = 'YouTube',
}) => {
  'key': key,
  'name': 'Preview',
  'type': type,
  'official': official,
  'site': site,
  'published_at': '2026-10-01T00:00:00Z',
};
TrailersRepository fixtureRepo({List<Uri>? requests}) => TrailersRepository(
  clock: () => DateTime.utc(2026, 11, 10),
  persist: false,
  client: TmdbCastService(
    fetch: (uri) async {
      requests?.add(uri);
      if (uri.path.endsWith('/videos')) {
        return {
          'results': [videoJson('abcdefghijk')],
        };
      }
      if (RegExp(r'/movie/\d+$').hasMatch(uri.path)) {
        return {
          ...movieJson(int.parse(uri.pathSegments.last)),
          'runtime': 120,
          'genres': [
            {'id': 1, 'name': 'Drama'},
          ],
          'videos': {
            'results': [videoJson('abcdefghijk')],
          },
          'release_dates': {
            'results': [
              {
                'iso_3166_1': 'CA',
                'release_dates': [
                  {'certification': 'PG'},
                ],
              },
            ],
          },
        };
      }
      final page = int.tryParse(uri.queryParameters['page'] ?? '1') ?? 1;
      return {
        'page': page,
        'total_pages': 2,
        'results': [movieJson(page * 10 + 1), movieJson(page * 10 + 2)],
      };
    },
  ),
);

class MatchProvider extends FakeProvider {
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    const ContentItem(
      id: 'provider-1',
      name: 'Movie 1 (2027)',
      type: ContentType.movies,
      categoryId: 'open',
    ),
    const ContentItem(
      id: 'provider-2',
      name: 'Movie 1 (2026)',
      type: ContentType.movies,
      categoryId: 'open',
    ),
    const ContentItem(
      id: 'provider-3',
      name: 'Movie 1',
      type: ContentType.movies,
      categoryId: 'open',
    ),
  ];
}

class VerityProvider extends FakeProvider {
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    for (final language in ['English', 'Hindi', 'Turkish', 'Tamil', 'Telugu'])
      ContentItem(
        id: 'verity-$language',
        name: 'Verity (2026) ($language)',
        type: ContentType.movies,
        categoryId: 'open',
      ),
    const ContentItem(
      id: 'wrong-year',
      name: 'Verity (2025) (English)',
      type: ContentType.movies,
      categoryId: 'open',
    ),
  ];
}

void main() {
  test(
    'cast details load while all artwork download slots are occupied',
    () async {
      final release = Completer<void>();
      final downloads = [
        for (var i = 0; i < 4; i++)
          ArtworkRepository.queue.run(
            'blocked-artwork-$i',
            () => release.future,
            priority: () => ArtworkPriority.visible,
          ),
      ];
      await Future<void>.delayed(Duration.zero);
      try {
        final repo = TrailersRepository(
          persist: false,
          client: TmdbCastService(
            persist: false,
            fetch: (uri) async {
              expect(
                uri.queryParameters['append_to_response'],
                'videos,release_dates,credits',
              );
              return {
                ...movieJson(123),
                'credits': {
                  'cast': [
                    {'name': 'Actor', 'character': 'Lead'},
                  ],
                },
                'videos': {
                  'results': [videoJson('abcdefghijk')],
                },
              };
            },
          ),
        );
        final movie = await repo
            .details(123)
            .timeout(const Duration(seconds: 2));
        expect(movie.cast.single.name, 'Actor');
      } finally {
        release.complete();
        await Future.wait(downloads);
      }
    },
  );
  test('optional video failure preserves movie details and cast', () async {
    final repo = TrailersRepository(
      persist: false,
      client: TmdbCastService(
        persist: false,
        fetch: (uri) async {
          if (uri.path.endsWith('/videos')) throw Exception('Unavailable');
          return {
            ...movieJson(123),
            'credits': {
              'cast': [
                {'name': 'Actor', 'character': 'Lead'},
              ],
            },
          };
        },
      ),
    );
    final movie = await repo.details(123);
    expect(movie.title, 'Movie 123');
    expect(movie.cast.single.name, 'Actor');
    expect(movie.video, isNull);
  });
  test(
    'trailer cast names roles and photos survive caching and video updates',
    () {
      final movie = TrailerMovie.fromJson({
        'id': 100,
        'title': 'Example',
        'credits': {
          'cast': [
            {
              'name': 'Actor',
              'character': 'Role',
              'profile_path': '/actor.jpg',
            },
          ],
        },
      });
      final restored = TrailerMovie.fromJson(movie.withVideo(null).toJson());
      expect(restored.cast.single.name, 'Actor');
      expect(restored.cast.single.character, 'Role');
      expect(restored.cast.single.profilePath, '/actor.jpg');
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'Bollywood uses Hindi Indian productions and upcoming date order',
    () async {
      final requests = <Uri>[];
      final repo = TrailersRepository(
        persist: false,
        clock: () => DateTime(2026, 11, 10),
        client: TmdbCastService(
          fetch: (uri) async {
            requests.add(uri);
            return {
              'results': [
                {...movieJson(1), 'release_date': '2027-02-01'},
                {...movieJson(2), 'release_date': '2026-11-11'},
                {...movieJson(3), 'release_date': '2026-11-10'},
                {...movieJson(4), 'release_date': ''},
              ],
            };
          },
        ),
      );
      final page = await repo.page(TrailerCollection.upcomingBollywood);
      expect(page.movies.map((movie) => movie.id), [2, 1]);
      expect(requests.single.queryParameters['with_original_language'], 'hi');
      expect(requests.single.queryParameters['with_origin_country'], 'IN');
      expect(
        requests.single.queryParameters['sort_by'],
        'primary_release_date.asc',
      );
      expect(
        TrailerCollection.upcomingBollywood.label,
        'Upcoming Bollywood Releases',
      );
    },
  );
  test(
    'upcoming, popular and now playing parse real shapes with region and paging',
    () async {
      final requests = <Uri>[];
      final repo = fixtureRepo(requests: requests);
      repo.locale('en-CA', 'CA');
      for (final c in TrailerCollection.values) {
        final page = await repo.page(c);
        expect(page.movies.length, 2);
        expect(page.totalPages, 2);
        expect(page.movies.first.id, 11);
      }
      expect(requests.any((u) => u.path.endsWith('/discover/movie')), true);
      expect(requests.any((u) => u.path.endsWith('/popular')), true);
      expect(requests.any((u) => u.path.endsWith('/now_playing')), true);
      expect(requests.first.queryParameters.containsKey('region'), false);
      expect(requests.first.queryParameters['with_original_language'], 'en');
      expect(
        requests
            .firstWhere((u) => u.path.endsWith('/now_playing'))
            .queryParameters['region'],
        'CA',
      );
      expect(requests.first.queryParameters['language'], 'en-CA');
      final second = await repo.page(TrailerCollection.upcoming, page: 2);
      expect(second.movies.first.id, 21);
      expect(second.movies.first.card.toString(), contains('/w300/'));
      expect(second.movies.first.poster.toString(), contains('/w342/'));
    },
  );
  test(
    'official trailer, other trailer, official teaser, then permitted preview',
    () {
      final videos = [
        videoJson('aaaaaaaaaaa', type: 'Clip'),
        videoJson('bbbbbbbbbbb', type: 'Teaser'),
        videoJson('ccccccccccc', type: 'Teaser'),
        videoJson('ddddddddddd', official: false),
        videoJson('eeeeeeeeeee'),
      ];
      expect(TrailerVideo.select(videos)?.key, 'eeeeeeeeeee');
      videos.removeLast();
      expect(TrailerVideo.select(videos)?.key, 'ddddddddddd');
      videos.removeLast();
      expect(TrailerVideo.select(videos)?.type, 'Teaser');
      expect(
        TrailerVideo.select([
          videoJson('invalid'),
          videoJson('abcdefghijk', site: 'Vimeo'),
          videoJson('abcdefghijk', type: 'Behind the Scenes'),
        ]),
        isNull,
      );
      expect(TrailerVideo.select([]), isNull);
    },
  );
  test(
    'details keep TMDB id, genres, runtime, certification and trailer',
    () async {
      final repo = fixtureRepo();
      repo.locale('en-CA', 'CA');
      final movie = await repo.details(99);
      expect(movie.id, 99);
      expect(movie.runtime, 120);
      expect(movie.genres, ['Drama']);
      expect(movie.certification, 'PG');
      expect(movie.video?.official, true);
      expect(TrailerMovie.fromJson(movie.toJson()).id, 99);
      expect(
        TrailerMovie(id: 1, title: 'Missing').dateLabel,
        'Release date TBA',
      );
      expect(TrailerMovie(id: 1, title: 'Missing').card, isNull);
    },
  );
  test(
    'deduplicates requests and refresh is not trapped by a cached Future',
    () async {
      var calls = 0;
      final repo = TrailersRepository(
        persist: false,
        client: TmdbCastService(
          fetch: (uri) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            return {
              'page': 1,
              'total_pages': 1,
              'results': [movieJson(1)],
            };
          },
        ),
      );
      await Future.wait([
        repo.page(TrailerCollection.upcoming),
        repo.page(TrailerCollection.upcoming),
      ]);
      expect(calls, 1);
      await repo.page(TrailerCollection.upcoming);
      await repo.page(TrailerCollection.upcoming);
      expect(calls, 1);
      await repo.page(TrailerCollection.upcoming, refresh: true);
      expect(calls, 2);
    },
  );
  test(
    'auth/rate errors are safe and stale cached data remains usable offline',
    () async {
      var now = DateTime.utc(2026, 11, 9);
      var fail = false;
      final repo = TrailersRepository(
        persist: false,
        clock: () => now,
        client: TmdbCastService(
          fetch: (uri) async {
            if (fail) throw const TmdbApiException(429);
            return {
              'page': 1,
              'total_pages': 1,
              'results': [movieJson(1)],
            };
          },
        ),
      );
      await repo.page(TrailerCollection.upcoming);
      now = now.add(const Duration(hours: 7));
      fail = true;
      final cached = await repo.page(TrailerCollection.upcoming);
      expect(cached.stale, true);
      expect(cached.movies.single.id, 1);
      final denied = TrailersRepository(
        persist: false,
        client: TmdbCastService(
          fetch: (_) async => throw const TmdbApiException(401),
        ),
      );
      await expectLater(
        denied.page(TrailerCollection.upcoming),
        throwsA(
          isA<TrailerDiscoveryError>().having(
            (e) => e.message,
            'message',
            contains('token'),
          ),
        ),
      );
      final slow = TrailersRepository(
        persist: false,
        timeout: const Duration(milliseconds: 5),
        client: TmdbCastService(
          fetch: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return {};
          },
        ),
      );
      await expectLater(
        slow.page(TrailerCollection.upcoming),
        throwsA(isA<TrailerDiscoveryError>()),
      );
    },
  );
  test(
    'popular collection filters missing trailers without fetching full details',
    () async {
      final paths = <String>[];
      final repo = TrailersRepository(
        persist: false,
        client: TmdbCastService(
          fetch: (u) async {
            paths.add(u.path);
            if (u.path.endsWith('/videos')) {
              return {
                'results': u.path.contains('/1/')
                    ? [videoJson('abcdefghijk')]
                    : [],
              };
            }
            return {
              'page': 1,
              'total_pages': 1,
              'results': [movieJson(1), movieJson(2)],
            };
          },
        ),
      );
      expect(
        (await repo.page(TrailerCollection.popular)).movies.map((m) => m.id),
        [1],
      );
      expect(paths.any((p) => RegExp(r'/movie/\d+$').hasMatch(p)), false);
    },
  );
  test(
    'Remind Me survives restart, is profile specific, and uses IDs',
    () async {
      final alice = TrailerReminders('alice'), bob = TrailerReminders('bob');
      const a = TrailerMovie(id: 1, title: 'Same name'),
          b = TrailerMovie(id: 2, title: 'Same name');
      await alice.toggle(a);
      await alice.toggle(b);
      final restarted = TrailerReminders('alice');
      await restarted.load();
      await bob.load();
      expect(restarted.items.length, 2);
      expect(bob.items, isEmpty);
      await restarted.toggle(a);
      expect(restarted.items.single.id, 2);
    },
  );
  test(
    'IPTV matching requires title AND year and respects locks/hidden titles',
    () async {
      final provider = MatchProvider();
      const movie = TrailerMovie(
        id: 123,
        title: 'Movie 1',
        releaseDate: '2027-04-10',
      );
      expect((await matchTrailerMovie(provider, movie)).map((m) => m.id), [
        'provider-1',
      ]);
      final locks = CategoryLocks.forProvider(provider);
      await locks.setTitleHidden(
        const ContentItem(
          id: 'provider-1',
          name: 'Movie 1',
          type: ContentType.movies,
        ),
        true,
      );
      expect(await matchTrailerMovie(provider, movie), isEmpty);
      expect(
        await matchTrailerMovie(
          provider,
          const TrailerMovie(id: 123, title: 'Movie 1'),
        ),
        isEmpty,
      );
    },
  );
  test('popular video rate limits stop scanning the remaining page', () async {
    var videos = 0;
    final repo = TrailersRepository(
      persist: false,
      client: TmdbCastService(
        fetch: (u) async {
          if (u.path.endsWith('/videos')) {
            videos++;
            throw const TmdbApiException(429);
          }
          return {
            'page': 1,
            'total_pages': 1,
            'results': List.generate(20, (i) => movieJson(i + 1)),
          };
        },
      ),
    );
    await expectLater(
      repo.page(TrailerCollection.popular),
      throwsA(
        isA<TrailerDiscoveryError>().having(
          (e) => e.message,
          'message',
          contains('too many'),
        ),
      ),
    );
    expect(videos, 4);
  });
  test(
    'upcoming excludes old, released-today and undated entries and sorts future releases',
    () async {
      final requests = <Uri>[];
      final repo = TrailersRepository(
        persist: false,
        clock: () => DateTime(2026, 11, 10, 23, 59),
        client: TmdbCastService(
          fetch: (u) async {
            requests.add(u);
            return {
              'page': 1,
              'total_pages': 2,
              'results': [
                {...movieJson(1), 'release_date': '2021-05-12'},
                {...movieJson(2), 'release_date': '2024-08-01'},
                {...movieJson(3), 'release_date': '2026-11-10'},
                {...movieJson(4), 'release_date': ''},
                {...movieJson(5), 'release_date': '2027-01-01'},
                {...movieJson(6), 'release_date': '2026-11-11'},
                {...movieJson(7), 'release_date': 'not-a-date'},
              ],
            };
          },
        ),
      );
      final first = await repo.page(TrailerCollection.upcoming);
      expect(first.movies.map((m) => m.id), [6, 5]);
      expect(first.totalPages, 2);
      final query = requests.single.queryParameters;
      expect(requests.single.path, '/3/discover/movie');
      expect(query['primary_release_date.gte'], '2026-11-11');
      expect(query['with_original_language'], 'en');
      expect(query.containsKey('region'), false);
      expect(query['sort_by'], 'primary_release_date.asc');
      // The same guard applies when the raw response is reused from cache.
      expect(
        (await repo.page(TrailerCollection.upcoming)).movies.map((m) => m.id),
        [6, 5],
      );
      expect(requests.length, 1);
      // Other collections intentionally retain already released films.
      expect(
        (await repo.page(
          TrailerCollection.nowPlaying,
        )).movies.any((m) => m.id == 1),
        true,
      );
    },
  );
  test(
    'upcoming date filter rolls over on the local calendar and applies to View All pages',
    () async {
      var now = DateTime(2026, 12, 31, 23, 59);
      final requests = <Uri>[];
      final repo = TrailersRepository(
        persist: false,
        clock: () => now,
        client: TmdbCastService(
          fetch: (u) async {
            requests.add(u);
            return {
              'page': int.parse(u.queryParameters['page']!),
              'total_pages': 3,
              'results': [
                {...movieJson(1), 'release_date': '2027-01-01'},
                {...movieJson(2), 'release_date': '2027-01-02'},
              ],
            };
          },
        ),
      );
      expect(
        (await repo.page(TrailerCollection.upcoming, page: 2)).movies.length,
        2,
      );
      expect(requests.last.queryParameters['page'], '2');
      expect(
        requests.last.queryParameters['primary_release_date.gte'],
        '2027-01-01',
      );
      now = DateTime(2027, 1, 1, 0, 1);
      expect(
        (await repo.page(
          TrailerCollection.upcoming,
          page: 2,
        )).movies.map((m) => m.id),
        [2],
      );
      expect(
        requests.last.queryParameters['primary_release_date.gte'],
        '2027-01-02',
      );
      expect(requests.length, 2);
    },
  );
  test(
    'Verity matches all catalog language variants without accepting a different year',
    () async {
      final provider = VerityProvider();
      final results = await matchTrailerMovie(
        provider,
        const TrailerMovie(id: 999, title: 'Verity', releaseDate: '2026-10-02'),
      );
      expect(results.length, 5);
      expect(results.map((i) => i.id), isNot(contains('wrong-year')));
      expect(catalogMovieTitle('Verity (2026) (Hindi) (4K)'), 'verity');
      expect(catalogMovieTitle('Johnny English'), 'johnny english');
      expect(catalogMovieTitle('The French Dispatch'), 'the french dispatch');
    },
  );
  test(
    'Hollywood upcoming releases use English and US origin filters',
    () async {
      final requests = <Uri>[];
      final repo = fixtureRepo(requests: requests);
      repo.locale('en-US', 'US');
      await repo.page(TrailerCollection.upcoming);
      expect(requests.first.queryParameters['with_original_language'], 'en');
      expect(requests.first.queryParameters['with_origin_country'], 'US');
      expect(requests.first.queryParameters.containsKey('region'), false);
      expect(
        requests.first.queryParameters['sort_by'],
        'primary_release_date.asc',
      );
    },
  );
  test(
    'Hindi movie details request Hindi-language video metadata when needed',
    () async {
      final requests = <Uri>[];
      final repo = TrailersRepository(
        persist: false,
        client: TmdbCastService(
          fetch: (u) async {
            requests.add(u);
            if (u.path.endsWith('/videos')) {
              return {
                'results': [videoJson('abcdefghijk')],
              };
            }
            return {
              ...movieJson(1),
              'original_language': 'hi',
              'videos': {'results': []},
            };
          },
        ),
      );
      final info = await repo.details(1);
      expect(info.video?.key, 'abcdefghijk');
      expect(requests.last.queryParameters['language'], 'hi-IN');
    },
  );
}
