import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/media_horizontal_rail.dart';

void main() {
  testWidgets(
    'focus moves during scrolling and rapid navigation settles on the latest tile',
    (tester) async {
      final key = GlobalKey<MediaHorizontalRailState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 450,
                height: 180,
                child: MediaHorizontalRail(
                  key: key,
                  count: 20,
                  width: 150,
                  height: 180,
                  up: () {},
                  down: () {},
                  itemBuilder: (i, node) => TextButton(
                    focusNode: node,
                    onPressed: () {},
                    child: Text('Tile $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.focusAt(2);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(key.currentState!.node(3).hasFocus, isTrue);
      await tester.pump(const Duration(milliseconds: 70));
      expect(key.currentState!.controller.offset, greaterThan(0));
      expect(key.currentState!.controller.offset, lessThan(150));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(key.currentState!.current, 4);
      expect(key.currentState!.node(4).hasFocus, isTrue);
      expect(key.currentState!.controller.offset % 150, closeTo(0, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a new category never inherits the previous category scroll offset',
    (tester) async {
      final first = GlobalKey<MediaHorizontalRailState>(),
          second = GlobalKey<MediaHorizontalRailState>();
      final showFirst = ValueNotifier(true);
      final bucket = PageStorageBucket();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: bucket,
              child: SizedBox(
                key: const PageStorageKey('series-catalog'),
                width: 503,
                height: 180,
                child: ValueListenableBuilder<bool>(
                  valueListenable: showFirst,
                  builder: (_, value, _) => MediaHorizontalRail(
                    key: value ? first : second,
                    count: 20,
                    width: 148,
                    height: 180,
                    up: () {},
                    down: () {},
                    itemBuilder: (index, node) => TextButton(
                      focusNode: node,
                      onPressed: () {},
                      child: Text('Tile $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final move = first.currentState!.focusAt(8);
      await tester.pumpAndSettle();
      await move;
      await tester.pumpAndSettle();
      expect(first.currentState!.controller.offset, greaterThan(0));
      showFirst.value = false;
      await tester.pumpAndSettle();
      expect(second.currentState!.controller.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      showFirst.dispose();
    },
  );

  testWidgets(
    'remote row scrolling keeps complete tiles at the left edge including the last page',
    (tester) async {
      final key = GlobalKey<MediaHorizontalRailState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 503,
                height: 180,
                child: MediaHorizontalRail(
                  key: key,
                  count: 11,
                  width: 148,
                  height: 180,
                  up: () {},
                  down: () {},
                  itemBuilder: (index, node) => Padding(
                    padding: const EdgeInsets.all(4),
                    child: TextButton(
                      focusNode: node,
                      onPressed: () {},
                      child: Text('Tile $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await key.currentState!.focusAt(0);
      await tester.pumpAndSettle();
      for (var index = 0; index < 11; index++) {
        if (index > 0) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
        }
        final offset = key.currentState!.controller.offset;
        expect(offset / 148, closeTo((offset / 148).roundToDouble(), .001));
        expect(key.currentState!.current, index);
        final focused =
            key.currentState!.node(index).context!.findRenderObject()
                as RenderBox;
        final viewport =
            key.currentState!.controller.position.viewportDimension;
        expect(viewport, 503);
        expect(focused.size.width, lessThanOrEqualTo(148));
      }
      final lastOffset = key.currentState!.controller.offset;
      await key.currentState!.focusAt(10);
      await tester.pumpAndSettle();
      expect(key.currentState!.controller.offset, lastOffset);
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
      }
      expect(key.currentState!.controller.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
