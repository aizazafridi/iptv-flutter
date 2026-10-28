import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/tv_guide_screen.dart';
import 'live_stream_recovery_test.dart' show RecoveryEngine;
import 'tv_guide_screen_test.dart' show GuideProvider;

class StableEngine extends RecoveryEngine {
  int surfaces = 0, builds = 0;
  @override
  Widget surface() {
    surfaces++;
    return Builder(
      builder: (_) {
        builds++;
        return const ColoredBox(color: Colors.black);
      },
    );
  }
}

void main() {
  testWidgets(
    'guide and programme focus preserve the active engine and video surface',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final engine = StableEngine();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: PlayerScreen(
            liveTvMode: true,
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Channel',
              isLive: true,
            ),
            item: const ContentItem(
              id: '1',
              name: 'Channel Alpha',
              type: ContentType.live,
            ),
            provider: GuideProvider(),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = engine.builds;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('TV Guide'));
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsOneWidget);
      expect(engine.surfaces, 1);
      expect(engine.opens, 1);
      expect(engine.builds, before);
      final programme = find.text('Programme 2');
      Focus.of(tester.element(programme)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(engine.surfaces, 1);
      expect(engine.opens, 1);
      expect(engine.builds, before);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      expect(find.byType(TvGuideScreen), findsNothing);
      expect(engine.opens, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
