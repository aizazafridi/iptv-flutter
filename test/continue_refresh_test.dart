import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final cards in [false, true]) {
    testWidgets(
      'Continue Watching updates immediately for saves, completion and clear (cards: $cards)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = FakeProvider();
        final appearance = AppAppearance();
        await appearance.load();
        await appearance.setCards(ContentType.movies, cards);
        final history = WatchHistory.forProvider(provider);
        const item = ContentItem(
          id: 'unique',
          name: 'Recently watched movie',
          type: ContentType.movies,
        );
        WatchEntry progress(int seconds) => WatchEntry(
          item,
          null,
          Duration(seconds: seconds),
          const Duration(minutes: 10),
          DateTime.now(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: BrowseScreen(
              provider: provider,
              type: ContentType.movies,
              appearance: appearance,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!cards) {
          await tester.tap(find.text('Continue watching'));
          await tester.pumpAndSettle();
        }
        expect(find.text(item.name), findsNothing);
        await history.save(progress(60));
        await tester.pumpAndSettle();
        expect(find.text(item.name), findsOneWidget);
        await history.save(progress(600));
        await tester.pumpAndSettle();
        expect(find.text(item.name), findsNothing);
        await history.save(progress(100));
        await tester.pumpAndSettle();
        expect(find.text(item.name), findsOneWidget);
        await history.clear();
        await tester.pumpAndSettle();
        expect(find.text(item.name), findsNothing);
        expect(
          (await history.latest(item))!.position,
          const Duration(seconds: 100),
        );
        await tester.pumpWidget(const SizedBox());
        appearance.dispose();
        provider.dispose();
      },
    );
  }
}
