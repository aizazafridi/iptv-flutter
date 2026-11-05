import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/player_settings_drawer.dart';

void main() {
  testWidgets(
    'record control is below aspect ratio and toggles without closing',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              child: PlayerSettingsDrawer(
                autoplay: null,
                rate: 1,
                seekSeconds: 10,
                ratio: 'Original',
                allowSpeed: true,
                onAutoplay: (_) async {},
                onRate: (_) async {},
                onSeek: (_) async {},
                onRatio: (_) async {},
                onRecord: () async {
                  calls++;
                },
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Record')).dy,
        greaterThan(tester.getTopLeft(find.text('Aspect Ratio')).dy),
      );
      await tester.ensureVisible(find.text('Start recording'));
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Stop recording'), findsOneWidget);
      await tester.tap(find.text('Stop recording'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Start recording'), findsOneWidget);
    },
  );
}
