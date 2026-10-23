import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/category_sidebar_item.dart';
import 'package:iptv_flutter/presentation/live_health_indicator.dart';

void main() {
  testWidgets('category highlight follows remote focus down and up', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListView(
              children: [
                CategorySidebarItem(
                  label: 'First',
                  autofocus: true,
                  onTap: () {},
                ),
                CategorySidebarItem(label: 'Second', onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Color? textColor(String title) =>
        tester.widget<Text>(find.text(title)).style?.color;
    expect(textColor('First'), const Color(0xff64b5f6));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(textColor('Second'), const Color(0xff64b5f6));
    expect(textColor('First'), Colors.white70);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(textColor('First'), const Color(0xff64b5f6));
    expect(textColor('Second'), Colors.white70);
  });
  testWidgets('health reports progress buffering and stalled playback', (
    tester,
  ) async {
    Future<void> show(
      int seconds, {
      bool buffering = false,
      bool reconnecting = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiveHealthIndicator(
            position: Duration(seconds: seconds),
            playing: true,
            starting: false,
            buffering: buffering,
            reconnecting: reconnecting,
          ),
        ),
      );
      await tester.pump();
    }

    await show(0);
    expect(find.text('Checking'), findsOneWidget);
    await show(1);
    expect(find.text('Good'), findsOneWidget);
    await show(2, buffering: true);
    expect(find.text('Unstable'), findsOneWidget);
    await show(2, reconnecting: true);
    expect(find.text('Reconnecting'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
