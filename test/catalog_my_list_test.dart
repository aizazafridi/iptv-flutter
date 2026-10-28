import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'series_catalog_screen_test.dart' show CatalogProvider;
import 'movie_catalog_screen_test.dart' show MovieProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets(
      '$type orders Continue Watching, My List, Recently Added and refreshes saves',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = type == ContentType.movies
            ? MovieProvider()
            : CatalogProvider();
        final items = provider.titles('0');
        final list = MyList.forProvider(provider);
        await list.toggle(items[3]);
        await WatchHistory.forProvider(provider).save(
          WatchEntry(
            items[1],
            null,
            const Duration(minutes: 2),
            const Duration(minutes: 90),
            DateTime.now(),
          ),
        );
        final key = GlobalKey<SeriesCatalogScreenState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SeriesCatalogScreen(
                key: key,
                type: type,
                provider: provider,
                onNavigation: () {},
                onSettings: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        key.currentState!.focusEntry();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('Continue Watching'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('My List'), findsOneWidget);
        final cards = tester.widgetList<SeriesPosterCard>(
          find.byType(SeriesPosterCard),
        );
        expect(
          cards.firstWhere((c) => c.focusNode?.hasFocus == true).item.id,
          items[3].id,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('Recently Added'), findsOneWidget);
        await list.toggle(items[3]);
        await tester.pumpAndSettle();
        expect(find.text('My List'), findsNothing);
        await list.toggle(items[4]);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<SeriesPosterCard>(find.byType(SeriesPosterCard))
              .firstWhere((c) => c.focusNode?.hasFocus == true)
              .item
              .id,
          items[4].id,
        );
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
      },
    );
  }
}
