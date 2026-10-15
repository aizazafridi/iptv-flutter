import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'My list persists all types, isolates accounts and serializes concurrent saves',
    () async {
      final list = MyList('a');
      final titles = [
        for (final type in ContentType.values)
          ContentItem(id: '42', name: type.label, type: type),
      ];
      await Future.wait(titles.map(list.toggle));
      final restored = MyList('a');
      for (final type in ContentType.values) {
        expect((await restored.items(type)).single.type, type);
        expect(await MyList('b').items(type), isEmpty);
      }
      await restored.toggle(titles[1]);
      expect(await MyList('a').items(ContentType.movies), isEmpty);
    },
  );
  test(
    'clear watch history removes persisted progress for only one account',
    () async {
      final a = WatchHistory('a'), b = WatchHistory('b');
      const movie = ContentItem(
        id: '42',
        name: 'Movie',
        type: ContentType.movies,
      );
      final entry = WatchEntry(
        movie,
        null,
        const Duration(minutes: 2),
        const Duration(minutes: 10),
        DateTime.utc(2026),
      );
      await a.save(entry);
      await b.save(entry);
      await a.clear();
      expect(await a.entries(), isEmpty);
      expect(await WatchHistory('a').entries(), isEmpty);
      expect((await WatchHistory('b').entries()).length, 1);
    },
  );
  for (final type in ContentType.values) {
    testWidgets('save and remove ${type.name} from My list', (tester) async {
      final provider = FakeProvider();
      WatchHistory.attach(
        provider,
        ProviderConfig(
          providerId: 'fixture',
          server: 'https://example.com',
          username: type.name,
          password: 'fixture',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(provider: provider, type: type),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('English (4K)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to My list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My list'));
      await tester.pumpAndSettle();
      expect(find.text('Example title'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from My list'));
      await tester.pumpAndSettle();
      expect(find.text('Example title'), findsNothing);
    });
  }
}
