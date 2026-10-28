import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test(
    'cached poster lookup never searches the network and reuses resolved URLs',
    () async {
      var calls = 0;
      final service = TmdbArtworkService(
        persist: false,
        client: TmdbCastService(
          persist: false,
          fetch: (_) async {
            calls++;
            return {
              'results': [
                {'id': 1, 'title': 'Example', 'poster_path': '/example.jpg'},
              ],
            };
          },
        ),
      );
      const item = ContentItem(
        id: '1',
        name: 'Example',
        type: ContentType.movies,
      );
      expect(await service.cachedPoster(item), isNull);
      expect(calls, 0);
      final poster = await service.poster(item);
      expect(poster, isNotNull);
      expect(await service.cachedPoster(item), poster);
      expect(calls, 1);
    },
  );

  test(
    'series details resolve fallback backdrops by TMDB ID without a title-only search',
    () async {
      final calls = <String>[];
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          calls.add(uri.path);
          return {'backdrop_path': '/series.jpg'};
        },
      );
      final artwork = TmdbArtworkService(client: client, persist: false);
      const details = MediaDetails(
        item: ContentItem(
          id: 'english',
          name: 'The Last of Us English',
          type: ContentType.series,
        ),
        synopsis: '',
        tmdbId: 100088,
      );
      expect(
        (await artwork.detailsBackdrop(details))!.path,
        '/t/p/w1280/series.jpg',
      );
      await artwork.detailsBackdrop(details);
      expect(calls, ['/3/tv/100088']);
    },
  );

  test(
    'movie logos prefer English, use provider TMDB id and cache results',
    () async {
      var calls = 0;
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          calls++;
          expect(uri.path, '/3/movie/42/images');
          expect(uri.queryParameters['include_image_language'], 'en,null');
          return {
            'logos': [
              {
                'file_path': '/foreign.png',
                'iso_639_1': 'fr',
                'vote_average': 10,
              },
              {
                'file_path': '/neutral.png',
                'iso_639_1': null,
                'vote_average': 9,
              },
              {
                'file_path': '/english.png',
                'iso_639_1': 'en',
                'vote_average': 7,
              },
            ],
          };
        },
      );
      final service = TmdbArtworkService(client: client, persist: false);
      const info = MediaDetails(
        item: ContentItem(id: 'film', name: 'Movie', type: ContentType.movies),
        synopsis: '',
        tmdbId: 42,
      );
      final logo = await service.titleLogo(info);
      expect(logo.toString(), 'https://image.tmdb.org/t/p/w500/english.png');
      expect(await service.titleLogo(info), logo);
      expect(calls, 1);
    },
  );
  test(
    'no suitable title logo falls back without using foreign artwork',
    () async {
      final client = TmdbCastService(
        persist: false,
        fetch: (_) async => {
          'logos': [
            {'file_path': '/foreign.png', 'iso_639_1': 'fr'},
          ],
        },
      );
      expect(
        await TmdbArtworkService(client: client, persist: false).titleLogo(
          const MediaDetails(
            item: ContentItem(
              id: 'film',
              name: 'Movie',
              type: ContentType.movies,
            ),
            synopsis: '',
            tmdbId: 42,
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'series backdrop uses TV search, exact title and first-air year, then caches',
    () async {
      var calls = 0;
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          calls++;
          expect(uri.path, '/3/search/tv');
          expect(uri.queryParameters['query'], 'Dexter: Resurrection');
          expect(uri.queryParameters['first_air_date_year'], '2025');
          return {
            'results': [
              {
                'id': 1,
                'name': 'Dexter: Resurrection',
                'first_air_date': '2025-07-11',
                'backdrop_path': '/dexter.jpg',
              },
            ],
          };
        },
      );
      final service = TmdbArtworkService(client: client, persist: false);
      const item = ContentItem(
        id: 'dexter',
        name: 'Dexter: Resurrection (2025)',
        type: ContentType.series,
      );
      final rows = await Future.wait([
        service.backdrop(item),
        service.backdrop(item),
      ]);
      expect(
        rows.first.toString(),
        'https://image.tmdb.org/t/p/w780/dexter.jpg',
      );
      await service.backdrop(item);
      expect(calls, 1);
    },
  );
  test('movie fallback fetches details if search has no backdrop', () async {
    final client = TmdbCastService(
      persist: false,
      fetch: (uri) async {
        if (uri.path == '/3/search/movie') {
          return {
            'results': [
              {
                'id': 4922,
                'title': 'The Curious Case of Benjamin Button',
                'release_date': '2008-12-25',
              },
            ],
          };
        }
        expect(uri.path, '/3/movie/4922');
        return {'backdrop_path': '/benjamin.jpg'};
      },
    );
    final service = TmdbArtworkService(client: client, persist: false);
    expect(
      (await service.backdrop(
        const ContentItem(
          id: 'film',
          name: 'The Curious Case of Benjamin Button (2008)(4K)',
          type: ContentType.movies,
        ),
      )).toString(),
      'https://image.tmdb.org/t/p/w780/benjamin.jpg',
    );
  });
  test('ambiguous or unavailable images retain poster fallback', () async {
    final client = TmdbCastService(
      persist: false,
      fetch: (_) async => {
        'results': [
          {'id': 1, 'title': 'Movie', 'backdrop_path': '/a.jpg'},
          {'id': 2, 'title': 'Movie', 'backdrop_path': '/b.jpg'},
        ],
      },
    );
    expect(
      await TmdbArtworkService(client: client, persist: false).backdrop(
        const ContentItem(id: 'film', name: 'Movie', type: ContentType.movies),
      ),
      isNull,
    );
    expect(
      await TmdbArtworkService(
        client: TmdbCastService(),
        persist: false,
      ).backdrop(
        const ContentItem(id: 'film', name: 'Movie', type: ContentType.movies),
      ),
      isNull,
    );
  });
}
