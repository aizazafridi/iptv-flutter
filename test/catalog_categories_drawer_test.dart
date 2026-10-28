import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/catalog_categories_drawer.dart';

Category category(String id, String name) =>
    Category(id, name, ContentType.movies);
void main() {
  test('conservative classification preserves IDs and duplicate names', () {
    final data = [
      category('a', 'ENGLISH | FHD 2026'),
      category('b', 'ENGLISH | FHD 2026'),
      category('c', 'ENGLISH | 4K'),
      category('d', 'ENGLISH | HINDI DUBBED'),
      category('e', 'ENGLISH | 2025 CAM'),
      category('f', 'FRENCH | FHD 2026'),
      category('g', 'Sports 4K collection'),
      category('', 'Missing'),
    ];
    final grouped = groupCatalogCategories(data);
    expect(grouped['English FHD']!.map((c) => c.id), ['a', 'b']);
    expect(grouped['Other Categories']!.map((c) => c.id), ['f', 'g']);
    expect(grouped['CAM Releases']!.single.id, 'e');
    expect(grouped.values.expand((v) => v), hasLength(7));
    expect(data.first.name, 'ENGLISH | FHD 2026');
  });
  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets(
      'drawer remote expansion, selection, restoration and Back at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final opener = FocusNode();
        addTearDown(opener.dispose);
        String? selected;
        final data = [
          category('year', 'ENGLISH | FHD 2026'),
          category('other', 'Unknown provider name'),
        ];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  focusNode: opener,
                  child: const Text('Open'),
                  onPressed: () async {
                    final result = await showCatalogCategoriesDrawer(
                      context,
                      categories: data,
                      allLabel: 'All Movies',
                      selectedId: selected,
                    );
                    if (result != null) selected = result.id;
                    opener.requestFocus();
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'all');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('ENGLISH | FHD 2026'), findsOneWidget);
        expect(selected, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(selected, 'year');
        expect(opener.hasFocus, isTrue);
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus!.debugLabel, 'category:year');
        expect(find.byIcon(Icons.check), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'heading:English FHD',
        );
        expect(find.text('ENGLISH | FHD 2026'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(selected, 'year');
        expect(opener.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('hundreds of categories lazily restore selected row', (
    tester,
  ) async {
    final data = List.generate(
      500,
      (i) => category('$i', 'Provider category $i'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => showCatalogCategoriesDrawer(
                context,
                categories: data,
                allLabel: 'All Series',
                selectedId: '490',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'category:490');
    expect(find.text('Provider category 490'), findsOneWidget);
    expect(find.text('Provider category 0'), findsNothing);
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'category:498');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty categories still offer All and close control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Open'),
              onPressed: () => showCatalogCategoriesDrawer(
                context,
                categories: [],
                allLabel: 'All Movies',
                selectedId: 'removed',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'all');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus!.debugLabel, 'close categories');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('catalog-categories-drawer')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
