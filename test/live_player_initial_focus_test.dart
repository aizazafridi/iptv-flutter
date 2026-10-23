import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'live_stream_recovery_test.dart' show RecoveryEngine;

void main() {
  testWidgets(
    'Live TV starts without focused controls and first remote press focuses without activating',
    (tester) async {
      final engine = RecoveryEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Channel',
              isLive: true,
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'live video surface',
      );
      final pause = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Pause',
        ),
      );
      expect(pause.focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(pause.focusNode!.hasPrimaryFocus, isTrue);
      expect(engine.pauses, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
