import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/catalog_index.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/search_screen.dart';
import 'widget_test.dart' as fixture;

class ActorProvider extends fixture.FakeProvider {
  int detailCalls = 0, active = 0, maxActive = 0;
  bool fail = false;
  @override
  Future<MediaDetails> getMovieDetails(ContentItem item) async {
    detailCalls++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(Duration.zero);
    active--;
    if (fail) throw const ProviderException('Unavailable');
    return MediaDetails(
      item: item,
      synopsis: 'Synopsis',
      cast: item.id == '88' ? 'Tom Hanks, Rita Wilson' : 'Other Actor',
    );
  }

  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) async =>
      SeriesDetails(await getMovieDetails(item), const []);
}

void main() {
  const movie = ContentItem(
    id: '88',
    name: 'A different title',
    type: ContentType.movies,
  );
  test(
    'actor matches without title match and caches successful metadata',
    () async {
      final provider = ActorProvider(), index = CatalogIndex(ActorProvider());
      final cache = CatalogIndex.forProvider(provider);
      expect(identical(cache, CatalogIndex.forProvider(provider)), isTrue);
      expect(index.matches(movie, 'Tom Hanks'), isFalse);
      await cache.enrich([movie], cancelled: () => false, onProgress: () {});
      expect(cache.matches(movie, 'TOM hanks'), isTrue);
      expect(cache.matches(movie, 'different hanks'), isTrue);
      await cache.enrich([movie], cancelled: () => false, onProgress: () {});
      expect(provider.detailCalls, 1);
    },
  );
  test(
    'catalog cast needs no details and provider caches are isolated',
    () async {
      final provider = ActorProvider(),
          cache = CatalogIndex.forProvider(ActorProvider());
      const item = ContentItem(
        id: '88',
        name: 'Example',
        type: ContentType.series,
        cast: 'Tom Hanks',
      );
      await CatalogIndex.forProvider(
        provider,
      ).enrich([item], cancelled: () => false, onProgress: () {});
      expect(provider.detailCalls, 0);
      expect(cache.known(movie), isFalse);
    },
  );
  test(
    'bounded workers stop scheduling when paused; failures can retry',
    () async {
      final provider = ActorProvider();
      final cache = CatalogIndex(provider);
      final rows = List.generate(
        8,
        (id) => ContentItem(id: '$id', name: 'Movie', type: ContentType.movies),
      );
      var cancelled = false;
      await cache.enrich(
        rows,
        cancelled: () => cancelled,
        onProgress: () => cancelled = true,
      );
      expect(provider.detailCalls, lessThanOrEqualTo(2));
      expect(provider.maxActive, lessThanOrEqualTo(2));
      provider.fail = true;
      await cache.enrich([movie], cancelled: () => false, onProgress: () {});
      expect(cache.failed, contains('movies:88'));
      provider.fail = false;
      await cache.enrich(
        [movie],
        cancelled: () => false,
        onProgress: () {},
        retryFailed: true,
      );
      expect(cache.matches(movie, 'Tom Hanks'), isTrue);
      expect(cache.failed, isEmpty);
    },
  );
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets('actor search finds ${type.name} across categories', (
      tester,
    ) async {
      final provider = ActorProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogSearchScreen(provider: provider, type: type),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'tom hanks');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('Another category title'), findsOneWidget);
      expect(find.text('Example title'), findsNothing);
      expect(find.text('Title and actor search ready'), findsOneWidget);
      expect(find.text('Tom Hanks, Rita Wilson'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'rita');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(provider.detailCalls, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
