import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/iptv_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'package:iptv_flutter/presentation/search_screen.dart';

class FakeProvider implements IptvProvider {
  @override
  String get displayName => 'Fixture';
  @override
  Set<ContentType> get supportedTypes => ContentType.values.toSet();
  @override
  Future<Account> connect() async => const Account('demo', 'Active', null);
  @override
  Future<List<Category>> getCategories(ContentType type) async => [
    Category('7', 'English (4K)', type),
  ];
  @override
  Future<List<ContentItem>> getItems(Category category) async => [
    ContentItem(id: '42', name: 'Example title', type: category.type),
  ];
  int catalogCalls = 0;
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async {
    catalogCalls++;
    return [
      ContentItem(id: '42', name: 'Example title', type: type),
      ContentItem(id: '88', name: 'Another category title', type: type),
    ];
  }

  @override
  Future<MediaDetails> getMovieDetails(ContentItem item) async =>
      MediaDetails(item: item, synopsis: 'Movie synopsis');
  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem item) async =>
      SeriesDetails(
        MediaDetails(item: item, synopsis: 'Series synopsis'),
        const [
          Episode(
            id: '50',
            title: 'Pilot',
            season: 1,
            number: 1,
            extension: 'mp4',
          ),
        ],
      );
  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async => PlaybackSource(
    uri: Uri.parse('https://example.com/video.mp4'),
    title: item.name,
  );
  @override
  void dispose() {}
}

void main() {
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets(
      'search ${type.name} across categories and keep catalog cached',
      (tester) async {
        final provider = FakeProvider();
        await tester.pumpWidget(
          MaterialApp(
            home: BrowseScreen(provider: provider, type: type),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Search all categories'));
        await tester.pumpAndSettle();
        expect(find.byType(CatalogSearchScreen), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'ANOTHER title');
        await tester.pumpAndSettle();
        expect(find.text('Another category title'), findsOneWidget);
        expect(find.text('Example title'), findsNothing);
        await tester.enterText(find.byType(TextField), 'missing');
        await tester.pumpAndSettle();
        expect(find.text('No matching titles found.'), findsOneWidget);
        expect(provider.catalogCalls, 1);
        await tester.enterText(find.byType(TextField), 'another');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Another category title'));
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsOneWidget);
      },
    );
  }

  testWidgets('category selection opens content and movie details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScreen(provider: FakeProvider(), type: ContentType.movies),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('English (4K)'));
    await tester.pumpAndSettle();
    expect(find.text('Example title'), findsOneWidget);
    await tester.tap(find.text('Example title'));
    await tester.pumpAndSettle();
    expect(find.text('Movie synopsis'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Example title'), findsOneWidget);
  });
  testWidgets('series details offer episode selection', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DetailsScreen(
          provider: FakeProvider(),
          item: const ContentItem(
            id: '99',
            name: 'Example series',
            type: ContentType.series,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Series synopsis'), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('1. Pilot'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });
}
