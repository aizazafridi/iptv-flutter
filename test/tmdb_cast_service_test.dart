import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/domain/models.dart';

const movie = ContentItem(
  id: 'provider123',
  name: 'Movie (2023)',
  type: ContentType.movies,
);
MediaDetails info({int? id}) => MediaDetails(
  item: movie,
  synopsis: '',
  releaseDate: '2023-04-12',
  tmdbId: id,
);
Map<String, dynamic> credits() => {
  'cast': [
    {
      'name': 'Second Actor',
      'character': 'Friend',
      'profile_path': null,
      'order': 1,
    },
    {
      'name': 'First Actor',
      'character': 'Hero',
      'profile_path': '/portrait.jpg',
      'order': 0,
    },
  ],
  'crew': [
    {
      'name': 'Director Name',
      'job': 'Director',
      'profile_path': '/director.jpg',
    },
  ],
};
void main() {
  test(
    'series language labels match the original title and aggregate cast roles',
    () async {
      expect(
        TmdbCastService.cleanSeriesTitle('The Last of Us Hindi'),
        'The Last of Us',
      );
      expect(
        TmdbCastService.cleanSeriesTitle('The Last of Us (2023) (English)'),
        'The Last of Us',
      );
      final calls = <Uri>[];
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          calls.add(uri);
          if (uri.path.endsWith('/search/tv')) {
            return {
              'results': [
                {
                  'id': 100088,
                  'name': 'The Last of Us',
                  'first_air_date': '2023-01-15',
                },
              ],
            };
          }
          return {
            'cast': [
              {
                'name': 'Pedro Pascal',
                'profile_path': '/pedro.jpg',
                'roles': [
                  {'character': 'Joel'},
                ],
              },
            ],
          };
        },
      );
      final result = await client.credits(
        const MediaDetails(
          item: ContentItem(
            id: 'hindi',
            name: 'The Last of Us Hindi',
            type: ContentType.series,
          ),
          synopsis: '',
        ),
      );
      expect(calls.first.queryParameters['query'], 'The Last of Us');
      expect(calls.last.path, '/3/tv/100088/aggregate_credits');
      expect(result.single.name, 'Pedro Pascal');
      expect(result.single.role, 'Joel');
      expect(result.single.photo!.path, '/t/p/w185/pedro.jpg');
    },
  );

  test(
    'provider trailing punctuation and quality separators do not remain in lookup titles',
    () {
      expect(
        TmdbCastService.cleanTitle(
          'The Curious Case of Benjamin Button (2008).',
        ),
        'The Curious Case of Benjamin Button',
      );
      expect(
        TmdbCastService.cleanTitle(
          'The Curious Case of Benjamin Button (2008) - 4K',
        ),
        'The Curious Case of Benjamin Button',
      );
    },
  );

  test('Benjamin Button bracketed quality tags do not block cast matching', () {
    expect(
      TmdbCastService.cleanTitle(
        'The Curious Case of Benjamin Button (2008)(4K)',
      ),
      'The Curious Case of Benjamin Button',
    );
    final client = TmdbCastService();
    expect(
      client.year(
        const MediaDetails(
          item: ContentItem(
            id: '1',
            name: 'Wonder Woman 1984 (2020)(4K)',
            type: ContentType.movies,
          ),
          synopsis: '',
        ),
      ),
      '2020',
    );
  });

  test('provider quality tags are stripped before title matching', () {
    expect(TmdbCastService.cleanTitle('EN: Movie (2023) FHD'), 'Movie');
  });
  test(
    'provider TMDB id retrieves credits directly, in billing order, and caches',
    () async {
      final requests = <Uri>[];
      final service = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          requests.add(uri);
          return credits();
        },
      );
      final results = await Future.wait([
        service.credits(info(id: 42)),
        service.credits(info(id: 42)),
      ]);
      expect(requests.single.path, '/3/movie/42/credits');
      expect(results.first.map((person) => person.name), [
        'First Actor',
        'Second Actor',
        'Director Name',
      ]);
      expect(
        results.first.first.photo.toString(),
        'https://image.tmdb.org/t/p/w185/portrait.jpg',
      );
      expect(results.first.first.role, 'Hero');
      expect(results.first[1].photo, isNull);
      await service.credits(info(id: 42));
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters.containsKey('api_key'), isFalse);
    },
  );
  test(
    'title/year matching only loads credits for an exact movie match',
    () async {
      final service = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          if (uri.path == '/3/search/movie') {
            expect(uri.queryParameters['query'], 'Movie');
            expect(uri.queryParameters['year'], '2023');
            return {
              'results': [
                {'id': 42, 'title': 'Movie', 'release_date': '2023-04-12'},
              ],
            };
          }
          expect(uri.path, '/3/movie/42/credits');
          return credits();
        },
      );
      expect(await service.credits(info()), hasLength(3));
    },
  );
  test(
    'ambiguous matches or different release years retain provider fallback',
    () async {
      for (final candidates in [
        [
          {'id': 1, 'title': 'Movie', 'release_date': '1999-01-01'},
        ],
        [
          {'id': 1, 'title': 'Movie', 'release_date': '2023-01-01'},
          {'id': 2, 'title': 'Movie', 'release_date': '2023-01-01'},
        ],
      ]) {
        var calls = 0;
        final service = TmdbCastService(
          persist: false,
          fetch: (_) async {
            calls++;
            return {'results': candidates};
          },
        );
        expect(await service.credits(info()), isEmpty);
        expect(calls, 1);
      }
    },
  );
  test(
    'missing token and failed network never prevent movie details',
    () async {
      expect(await TmdbCastService().credits(info()), isEmpty);
      final service = TmdbCastService(
        persist: false,
        fetch: (_) async => throw StateError('offline'),
      );
      expect(await service.credits(info()), isEmpty);
    },
  );
}
