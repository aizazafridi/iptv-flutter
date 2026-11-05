import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/catalog_poster_artwork.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  testWidgets(
    'visible missing poster retries and updates without reopening its card',
    (tester) async {
      var calls = 0;
      final service = TmdbArtworkService(
        persist: false,
        client: TmdbCastService(
          persist: false,
          fetch: (uri) async {
            calls++;
            if (calls == 1) {
              throw const FormatException('temporary metadata outage');
            }
            return {
              'results': [
                {
                  'id': 100088,
                  'name': 'The Last of Us',
                  'poster_path': '/recovered.jpg',
                },
              ],
            };
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPosterArtwork(
            item: const ContentItem(
              id: 'retry-visible',
              name: 'The Last of Us',
              type: ContentType.series,
            ),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CachedNetworkImage && w.imageUrl.endsWith('/recovered.jpg'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('offstage category posters do not fetch metadata until shown', (
    tester,
  ) async {
    var calls = 0, hidden = true;
    late StateSetter update;
    final service = TmdbArtworkService(
      persist: false,
      client: TmdbCastService(
        persist: false,
        fetch: (uri) async {
          calls++;
          return {
            'results': [
              {
                'id': 100088,
                'name': 'The Last of Us',
                'poster_path': '/visible-only.jpg',
              },
            ],
          };
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Offstage(
              offstage: hidden,
              child: CatalogPosterArtwork(
                item: const ContentItem(
                  id: 'offstage',
                  name: 'The Last of Us',
                  type: ContentType.series,
                ),
                service: service,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    update(() => hidden = false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'ambiguous posters use provider metadata instead of guessing between same-named shows',
    (tester) async {
      final paths = <String>[];
      final client = TmdbCastService(
        persist: false,
        fetch: (uri) async {
          paths.add(uri.path);
          if (uri.path.endsWith('/search/tv')) {
            return {
              'results': [
                {
                  'id': 4613,
                  'name': 'Band of Brothers',
                  'first_air_date': '2001-09-09',
                },
                {
                  'id': 999,
                  'name': 'Band of Brothers',
                  'first_air_date': '2008-10-25',
                },
              ],
            };
          }
          return {'poster_path': '/correct-poster.jpg'};
        },
      );
      final provider = _PosterProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 140,
            height: 210,
            child: CatalogPosterArtwork(
              item: const ContentItem(
                id: 'band',
                name: 'Band of Brothers',
                type: ContentType.series,
              ),
              provider: provider,
              service: TmdbArtworkService(client: client, persist: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.calls, 1);
      expect(paths, ['/3/search/tv', '/3/tv/4613']);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is CachedNetworkImage &&
              w.imageUrl.endsWith('/correct-poster.jpg'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final broken in [false, true]) {
    testWidgets(
      'missing/broken provider poster falls back to exact TMDB poster ($broken)',
      (tester) async {
        var calls = 0;
        final service = TmdbArtworkService(
          persist: false,
          client: TmdbCastService(
            persist: false,
            fetch: (uri) async {
              calls++;
              return {
                'results': [
                  {
                    'id': 100088,
                    'name': 'The Last of Us',
                    'poster_path': '/poster.jpg',
                  },
                ],
              };
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 140,
              height: 210,
              child: CatalogPosterArtwork(
                item: ContentItem(
                  id: '1',
                  name: 'The Last of Us Hindi',
                  type: ContentType.series,
                  artwork: broken
                      ? Uri.parse('https://example.com/broken.jpg')
                      : null,
                ),
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (broken && calls == 0) {
          final provider = tester.widget<CachedNetworkImage>(
            find.byType(CachedNetworkImage).first,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: provider.errorWidget!(
                tester.element(find.byType(CachedNetworkImage).first),
                'unused',
                Exception(),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(calls, 1);
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is CachedNetworkImage &&
                w.imageUrl.endsWith('/w185/poster.jpg'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('provider artwork does not request TMDB before failure', (
    tester,
  ) async {
    var calls = 0;
    final service = TmdbArtworkService(
      persist: false,
      client: TmdbCastService(
        persist: false,
        fetch: (_) async {
          calls++;
          return {};
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogPosterArtwork(
          item: ContentItem(
            id: '2',
            name: 'Title',
            type: ContentType.movies,
            artwork: Uri.parse('https://example.com/poster.jpg'),
          ),
          service: service,
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    expect(
      tester
          .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .imageUrl,
      'https://example.com/poster.jpg',
    );
    await tester.pumpWidget(const SizedBox());
  });
}

class _PosterProvider extends FakeProvider {
  int calls = 0;
  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) async {
    calls++;
    return SeriesDetails(
      MediaDetails(
        item: item,
        synopsis: '',
        tmdbId: 4613,
        releaseDate: '2001-09-09',
      ),
      const [],
    );
  }
}
