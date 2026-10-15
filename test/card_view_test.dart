import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/category_card_row.dart';
import 'widget_test.dart' show FakeProvider;

class RowProvider extends FakeProvider {
  int rowCalls = 0;
  @override
  Future<List<ContentItem>> getItems(Category category) async {
    rowCalls++;
    return List.generate(
      12,
      (index) =>
          ContentItem(id: '$index', name: 'Title $index', type: category.type),
    );
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'card preferences persist independently for each content type',
    () async {
      final appearance = AppAppearance();
      await appearance.setCards(ContentType.movies, true);
      await appearance.setCards(ContentType.live, true);
      await appearance.setCards(ContentType.live, false);
      final restored = AppAppearance();
      await restored.load();
      expect(restored.usesCards(ContentType.movies), isTrue);
      expect(restored.usesCards(ContentType.series), isFalse);
      expect(restored.usesCards(ContentType.live), isFalse);
      appearance.dispose();
      restored.dispose();
    },
  );
  for (final type in ContentType.values) {
    testWidgets('${type.name} horizontal rows, All and back', (tester) async {
      final appearance = AppAppearance();
      await appearance.setCards(type, true);
      final provider = RowProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(
            provider: provider,
            type: type,
            appearance: appearance,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('category-row:7'));
      if (row.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          row,
          300,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
      }
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(find.byType(CategoryCardRow), findsWidgets);
      final horizontal = find.descendant(
        of: row,
        matching: find.byType(ListView),
      );
      expect(
        tester.widget<ListView>(horizontal).scrollDirection,
        Axis.horizontal,
      );
      await tester.drag(horizontal, const Offset(-550, 0));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: horizontal,
        matching: find.byType(Scrollable),
      );
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
      );
      await tester.tap(find.descendant(of: row, matching: find.text('All')));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(provider.rowCalls, 1);
      if (type != ContentType.live) {
        await tester.tap(find.text('Title 0'));
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsOneWidget);
        await tester.tap(find.byType(BackButton).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(BackButton).first);
      await tester.pumpAndSettle();
      expect(find.byType(CategoryCardRow), findsWidgets);
      expect(provider.rowCalls, 1);
      await tester.pumpWidget(const SizedBox());
      appearance.dispose();
    });
  }
}
