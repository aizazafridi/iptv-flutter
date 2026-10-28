import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/omdb_ratings_service.dart';
import 'package:iptv_flutter/domain/models.dart';

const item = ContentItem(
  id: 'film',
  name: 'Movie (2008)(4K)',
  type: ContentType.movies,
);
const details = MediaDetails(
  item: item,
  synopsis: '',
  releaseDate: '2008-12-25',
);
Map<String, dynamic> response() => {
  'Response': 'True',
  'Title': 'Movie',
  'Year': '2008',
  'imdbID': 'tt0421715',
  'imdbRating': '7.8',
  'Ratings': [
    {'Source': 'Rotten Tomatoes', 'Value': '72%'},
    {'Source': 'Metacritic', 'Value': '70/100'},
  ],
};
void main() {
  test(
    'series ratings resolve TV external IDs and request OMDb series data',
    () async {
      final paths = <String>[];
      final metadata = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          paths.add(uri.path);
          return {'imdb_id': 'tt3581920'};
        },
      );
      final service = OmdbRatingsService(
        persist: false,
        metadataClient: metadata,
        fetch: (uri) async {
          expect(uri.queryParameters['type'], 'series');
          expect(uri.queryParameters['i'], 'tt3581920');
          return {
            'Response': 'True',
            'imdbID': 'tt3581920',
            'imdbRating': '8.4',
            'Ratings': [
              {'Source': 'Internet Movie Database', 'Value': '8.4/10'},
            ],
          };
        },
      );
      final ratings = await service.ratings(
        const MediaDetails(
          item: ContentItem(
            id: 'tlou',
            name: 'The Last of Us Hindi',
            type: ContentType.series,
          ),
          synopsis: '',
          tmdbId: 100088,
        ),
      );
      expect(paths, ['/3/tv/100088/external_ids']);
      expect(ratings.imdb, '8.4/10');
      expect(ratings.rottenTomatoes, isNull);
    },
  );

  test('verified TMDB-to-IMDb id avoids provider title mismatch', () async {
    final metadata = TmdbCastService(
      persist: false,
      fetch: (uri) async {
        expect(uri.path, '/3/movie/4922');
        return {'imdb_id': 'tt0421715'};
      },
    );
    final service = OmdbRatingsService(
      persist: false,
      metadataClient: metadata,
      fetch: (uri) async {
        expect(uri.queryParameters['i'], 'tt0421715');
        expect(uri.queryParameters.containsKey('t'), isFalse);
        return {...response(), 'Title': 'The Curious Case of Benjamin Button'};
      },
    );
    final result = await service.ratings(
      const MediaDetails(
        item: ContentItem(
          id: 'benjamin',
          name: 'Provider-specific Benjamin Button title',
          type: ContentType.movies,
        ),
        synopsis: '',
        tmdbId: 4922,
      ),
    );
    expect(result.imdb, '7.8/10');
    expect(result.rottenTomatoes, '72%');
  });

  test(
    'Benjamin Button leading article variations match only with the same year',
    () async {
      final service = OmdbRatingsService(
        persist: false,
        fetch: (_) async => {
          ...response(),
          'Title': 'The Curious Case of Benjamin Button',
        },
      );
      const matching = MediaDetails(
        item: ContentItem(
          id: 'benjamin',
          name: 'Curious Case of Benjamin Button (2008)(4K)',
          type: ContentType.movies,
        ),
        synopsis: '',
        releaseDate: '2008-12-25',
      );
      expect((await service.ratings(matching)).imdb, '7.8/10');
      expect((await service.ratings(matching)).rottenTomatoes, '72%');
      const wrongYear = MediaDetails(
        item: ContentItem(
          id: 'wrong',
          name: 'Curious Case of Benjamin Button (2009)',
          type: ContentType.movies,
        ),
        synopsis: '',
        releaseDate: '2009-01-01',
      );
      expect((await service.ratings(wrongYear)).isEmpty, isTrue);
    },
  );

  test(
    'parses IMDb and Rotten Tomatoes independently and rejects unavailable/invalid scores',
    () {
      final scores = MovieRatings.fromOmdb(response());
      expect(scores.imdb, '7.8/10');
      expect(scores.rottenTomatoes, '72%');
      final missing = MovieRatings.fromOmdb({
        'imdbRating': 'N/A',
        'Ratings': [
          {'Source': 'Rotten Tomatoes', 'Value': 'N/A'},
        ],
      });
      expect(missing.isEmpty, isTrue);
      final invalid = MovieRatings.fromOmdb({
        'imdbRating': '11',
        'Ratings': [
          {'Source': 'Rotten Tomatoes', 'Value': '101%'},
        ],
      });
      expect(invalid.isEmpty, isTrue);
    },
  );
  test(
    'title/year lookup strips provider tags and shares/caches requests',
    () async {
      var count = 0;
      final service = OmdbRatingsService(
        persist: false,
        apiKey: 'test-key',
        fetch: (uri) async {
          count++;
          expect(uri.scheme, 'https');
          expect(uri.host, 'www.omdbapi.com');
          expect(uri.queryParameters['t'], 'Movie');
          expect(uri.queryParameters['y'], '2008');
          return response();
        },
      );
      final scores = await Future.wait([
        service.ratings(details),
        service.ratings(details),
      ]);
      expect(scores.first.rottenTomatoes, '72%');
      await service.ratings(details);
      expect(count, 1);
    },
  );
  test('IMDb id lookup avoids title ambiguity', () async {
    final service = OmdbRatingsService(
      persist: false,
      fetch: (uri) async {
        expect(uri.queryParameters['i'], 'tt0421715');
        expect(uri.queryParameters.containsKey('t'), isFalse);
        return response();
      },
    );
    final scores = await service.ratings(
      const MediaDetails(item: item, synopsis: '', imdbId: 'tt0421715'),
    );
    expect(scores.imdb, '7.8/10');
  });
  test('wrong movie or year never supplies a score', () async {
    for (final changes in [
      {'Title': 'Other film'},
      {'Year': '1999'},
    ]) {
      final service = OmdbRatingsService(
        persist: false,
        fetch: (_) async => {...response(), ...changes},
      );
      expect((await service.ratings(details)).isEmpty, isTrue);
    }
  });
  test(
    'inactive keys, offline service and missing configuration never block details',
    () async {
      expect((await OmdbRatingsService().ratings(details)).isEmpty, isTrue);
      final inactive = OmdbRatingsService(
        persist: false,
        fetch: (_) async => {'Response': 'False', 'Error': 'Invalid API key!'},
      );
      expect((await inactive.ratings(details)).isEmpty, isTrue);
      final offline = OmdbRatingsService(
        persist: false,
        fetch: (_) async => throw StateError('offline'),
      );
      expect((await offline.ratings(details)).isEmpty, isTrue);
    },
  );
}
