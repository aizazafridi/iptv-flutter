import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;

void main() {
  testWidgets(
    'repeated Back cannot dismiss live exit confirmation; No stays and Yes exits',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerScreen(
                      liveTvMode: true,
                      source: PlaybackSource(
                        uri: Uri.parse('https://example.com/live'),
                        title: 'Channel',
                        isLive: true,
                      ),
                      engineFactory: FakeEngine.new,
                    ),
                  ),
                ),
                child: const Text('Open Live TV'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Live TV'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Live TV?'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.binding.handlePopRoute();
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Exit Live TV?'), findsOneWidget);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.text('Exit Live TV?'), findsNothing);
      expect(find.byType(PlayerScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit Live TV?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsNothing);
      expect(find.text('Open Live TV'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
