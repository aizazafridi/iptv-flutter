import 'dart:async';
import 'package:iptv_flutter/presentation/vod_player_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/trailer_source.dart';
import 'package:iptv_flutter/presentation/trailer_screen.dart';

void main() {
  testWidgets('exit stays responsive when the native player never replies', (
    tester,
  ) async {
    late TrailerBridge bridge;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => YoutubeTrailerScreen(
                  videoId: 'abcdefghijk',
                  title: 'Test',
                  embedBuilder: (_, value) {
                    bridge = value;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    bridge.evaluate = (_) => Completer<dynamic>().future;
    bridge.receive(['ready', true]);
    bridge.receive(['state', 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Exit trailer?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Exit trailer?'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.byType(YoutubeTrailerScreen), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
  test(
    'progress updates do not rebuild native video and duplicate states are ignored',
    () {
      final bridge = TrailerBridge();
      var changes = 0;
      bridge.addListener(() => changes++);
      bridge.receive(['ready', true]);
      bridge.receive(['state', 1]);
      bridge.receive(['state', 1]);
      for (var i = 0; i < 60; i++) {
        bridge.receive([
          'progress',
          [i, 120],
        ]);
      }
      expect(changes, 2);
      expect(bridge.position, 59);
      bridge.dispose();
    },
  );
  testWidgets(
    'video viewport stays fixed through loading, playback, error and retry',
    (tester) async {
      TrailerBridge? bridge;
      await tester.pumpWidget(
        MaterialApp(
          home: YoutubeTrailerScreen(
            videoId: 'abcdefghijk',
            title: 'Movie',
            embedBuilder: (_, b) {
              bridge = b;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      await tester.pump();
      final viewport = find.byKey(const ValueKey('trailer-video-viewport'));
      final size = tester.getRect(viewport);
      bridge!.receive(['ready', true]);
      bridge!.receive(['state', 1]);
      await tester.pump();
      expect(tester.getRect(viewport), size);
      bridge!.receive(['error', 5]);
      await tester.pump();
      expect(tester.getRect(viewport), size);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tester.getRect(viewport), size);
      expect(bridge!.state, -1);
      expect(bridge!.buffering, false);
      await tester.pump(const Duration(seconds: 26));
      expect(find.textContaining('too long to load'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('buffering after playback has a bounded recovery timeout', (
    tester,
  ) async {
    TrailerBridge? bridge;
    await tester.pumpWidget(
      MaterialApp(
        home: YoutubeTrailerScreen(
          videoId: 'abcdefghijk',
          title: 'Movie',
          embedBuilder: (_, b) {
            bridge = b;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    await tester.pump();
    bridge!.receive(['ready', true]);
    bridge!.receive(['state', 1]);
    await tester.pump(const Duration(seconds: 26));
    expect(bridge!.error, isNull);
    bridge!.receive(['state', 3]);
    await tester.pump(const Duration(seconds: 26));
    expect(find.textContaining('too long to load'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('YouTube links resolve only trusted hosts with valid IDs', () {
    for (final url in [
      'https://www.youtube.com/watch?v=abcdefghijk&t=10',
      'https://youtu.be/abcdefghijk?si=share',
      'https://m.youtube.com/watch?v=abcdefghijk',
      'https://www.youtube-nocookie.com/embed/abcdefghijk',
      'https://youtube.com/shorts/abcdefghijk',
    ]) {
      expect(youtubeTrailerId(Uri.parse(url)), 'abcdefghijk');
    }
    for (final url in [
      'https://youtube.com.evil.test/watch?v=abcdefghijk',
      'https://evil.test/abcdefghijk',
      'https://youtube.com/watch?v=short',
      'javascript:alert(1)',
      'https://youtube.com/watch?v=%3Cscript%3E',
    ]) {
      expect(youtubeTrailerId(Uri.parse(url)), isNull);
    }
    expect(
      isDirectTrailer(
        Uri.parse('https://cdn.example.test/trailer.mp4?token=secret'),
      ),
      true,
    );
    expect(
      isDirectTrailer(Uri.parse('https://cdn.example.test/trailer.m3u8')),
      true,
    );
    expect(isDirectTrailer(Uri.parse('file:///video.mp4')), false);
    expect(isDirectTrailer(Uri.parse('https://example.test/watch')), false);
  });
  test(
    'embedded document identifies app and preserves official player controls',
    () {
      final html = youtubeTrailerDocument('abcdefghijk');
      expect(html, contains('https://www.youtube.com/iframe_api'));
      expect(html, contains('controls=1'));
      expect(html, contains('<iframe id="player"'));
      expect(html, contains('enablejsapi=1'));
      expect(html, contains('allow="autoplay; encrypted-media"'));
      expect(html, contains('<script async src='));
      expect(html, contains('origin=${Uri.encodeComponent(trailerOrigin)}'));
      expect(html, contains('strict-origin-when-cross-origin'));
      expect(() => youtubeTrailerDocument('</script>'), throwsFormatException);
      expect(trailerErrorMessage(150), contains('does not allow'));
      expect(trailerErrorMessage(100), contains('private'));
    },
  );
  testWidgets(
    'trailer controls work in app and Esc restores the details route',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TrailerBridge? bridge;
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => YoutubeTrailerScreen(
                      videoId: 'abcdefghijk',
                      title: 'A long movie title',
                      embedBuilder: (_, b) {
                        bridge = b;
                        b.evaluate = (js) async {
                          commands.add(js);
                          return null;
                        };
                        return const ColoredBox(color: Colors.black);
                      },
                    ),
                  ),
                ),
                child: const Text('Trailer'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Trailer'));
      await tester.pumpAndSettle();
      bridge!.receive(['ready', true]);
      bridge!.receive([
        'progress',
        [12, 120],
      ]);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(commands, contains('window.trailerToggle();'));
      expect(find.byType(VodPlayerControls), findsNothing);
      expect(find.text('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(
        commands.where((c) => c == 'window.trailerToggle();'),
        hasLength(3),
      );
      bridge!.receive(['state', 1]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Exit trailer?'), findsOneWidget);
      expect(find.byType(YoutubeTrailerScreen), findsOneWidget);
      expect(commands.last, contains('pauseVideo'));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Exit trailer?'), findsNothing);
      expect(commands.last, contains('playVideo'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Exit trailer?'), findsOneWidget);
      await tester.tap(find.text('Exit trailer'));
      await tester.pumpAndSettle();
      expect(find.byType(YoutubeTrailerScreen), findsNothing);
      expect(find.text('Trailer'), findsOneWidget);
    },
  );
  testWidgets('embedding failure stays in app and offers close/retry', (
    tester,
  ) async {
    TrailerBridge? bridge;
    await tester.pumpWidget(
      MaterialApp(
        home: YoutubeTrailerScreen(
          videoId: 'abcdefghijk',
          title: 'Movie',
          embedBuilder: (_, b) {
            bridge = b;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    bridge!.receive(['error', 150]);
    await tester.pump();
    expect(
      find.text('This trailer does not allow playback inside apps.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unavailable native WebView fails inside the app instead of creating a player',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: YoutubeTrailerScreen(videoId: 'abcdefghijk', title: 'Movie'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('The embedded trailer player is unavailable on this device.'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'trailer keeps native controls and a stable fullscreen viewport',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TrailerBridge? bridge;
      await tester.pumpWidget(
        MaterialApp(
          home: YoutubeTrailerScreen(
            videoId: 'abcdefghijk',
            title: 'Movie',
            embedBuilder: (_, b) {
              bridge = b;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pump();
      bridge!.receive(['ready', true]);
      bridge!.receive([
        'progress',
        [15, 120],
      ]);
      bridge!.receive(['state', 1]);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(VodPlayerControls), findsNothing);
      final initial = tester
          .getSize(find.byKey(const ValueKey('trailer-video-viewport')))
          .height;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(VodPlayerControls), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('trailer-video-viewport')))
            .height,
        initial,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(VodPlayerControls), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
