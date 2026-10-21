import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/video_display.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;

class DisplayPlayer extends FakeEngine implements VideoDisplayEngine {
  @override
  VideoDisplay videoDisplay = const VideoDisplay();
  @override
  void setVideoDisplay(VideoDisplay display) {
    videoDisplay = display;
  }
}

void main() {
  for (final live in [false, true]) {
    testWidgets(
      'top back arrow exits ${live ? 'live' : 'VOD'} player immediately with controls visible',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('Previous screen')),
          ),
        );
        unawaited(
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen(
                source: PlaybackSource(
                  uri: Uri.parse('https://example.com/stream'),
                  title: 'Title',
                  isLive: live,
                ),
                engineFactory: () => DisplayPlayer(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final playPause = tester.widget<IconButton>(
          find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                (widget.tooltip == 'Play' || widget.tooltip == 'Pause'),
          ),
        );
        for (final states in [
          <WidgetState>{},
          {WidgetState.focused},
          {WidgetState.hovered},
          {WidgetState.pressed},
        ]) {
          expect(
            playPause.style!.backgroundColor!.resolve(states),
            Colors.transparent,
          );
        }
        expect(playPause.style!.foregroundColor!.resolve({}), Colors.white70);
        expect(
          playPause.style!.foregroundColor!.resolve({WidgetState.focused}),
          Colors.white,
        );
        expect(find.byTooltip('Zoom'), findsNothing);
        expect(find.byTooltip('Aspect ratio'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(PlayerScreen), findsNothing);
        expect(find.text('Previous screen'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
