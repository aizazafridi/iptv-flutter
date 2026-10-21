import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'widget_test.dart' show FakeProvider;
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/next_episode_countdown.dart';
import 'subtitle_test.dart' show FakeEngine;

class CompletedEngine extends FakeEngine implements CompletionPlaybackEngine {
  final endings = StreamController<bool>.broadcast();
  bool stopped = false;
  @override
  Stream<bool> get completed => endings.stream;
  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    await endings.close();
  }
}

const next = Episode(
  id: '2',
  title: 'The next episode',
  season: 1,
  number: 2,
  extension: 'mp4',
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('Play uses exactly the same circular styling as My List', (
    tester,
  ) async {
    final provider = FakeProvider();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailsScreen(
          provider: provider,
          item: const ContentItem(
            id: '42',
            name: 'Movie',
            type: ContentType.movies,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final play = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Play',
      ),
    );
    final list = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Add to My list',
      ),
    );
    expect(play.style!.shape!.resolve({}), isA<CircleBorder>());
    expect(
      play.style!.side!.resolve({WidgetState.focused}),
      list.style!.side!.resolve({WidgetState.focused}),
    );
    expect(
      play.style!.backgroundColor!.resolve({WidgetState.focused}),
      list.style!.backgroundColor!.resolve({WidgetState.focused}),
    );
    for (final states in [
      <WidgetState>{},
      {WidgetState.focused},
      {WidgetState.hovered},
      {WidgetState.pressed},
    ]) {
      expect(play.style!.backgroundColor!.resolve(states), Colors.transparent);
      expect(play.style!.foregroundColor!.resolve(states), Colors.white);
      expect(list.style!.backgroundColor!.resolve(states), Colors.transparent);
    }
    expect(find.text('Play'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  testWidgets(
    'vertical countdown fills for ten seconds and plays exactly once',
    (tester) async {
      var plays = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NextEpisodeCountdown(
              episode: next,
              onPlay: () => plays++,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(plays, 0);
      expect(
        tester
            .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
            .heightFactor,
        closeTo(0.5, 0.01),
      );
      expect(find.text('Next episode in 5 seconds'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(plays, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(plays, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(plays, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Cancel disposes the countdown and prevents automatic playback', (
    tester,
  ) async {
    var visible = true;
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, update) => Scaffold(
            body: visible
                ? NextEpisodeCountdown(
                    episode: next,
                    onPlay: () => plays++,
                    onCancel: () => update(() => visible = false),
                  )
                : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(plays, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'only end-of-media starts autoplay and the next episode is returned after ten seconds',
    (tester) async {
      final engine = CompletedEngine();
      final navigator = GlobalKey<NavigatorState>();
      Episode? requested;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Details')),
        ),
      );
      unawaited(
        navigator.currentState!
            .push<Episode>(
              MaterialPageRoute(
                builder: (_) => PlayerScreen(
                  source: PlaybackSource(
                    uri: Uri.parse('https://example.com/episode'),
                    title: 'Episode',
                  ),
                  nextEpisode: next,
                  engineFactory: () => engine,
                ),
              ),
            )
            .then((value) => requested = value),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NextEpisodeCountdown), findsNothing);
      engine.endings.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(NextEpisodeCountdown), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(requested, isNull);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(requested?.id, next.id);
      expect(engine.stopped, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Back cancels next-episode autoplay without exiting the player', (
    tester,
  ) async {
    final engine = CompletedEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: PlaybackSource(
            uri: Uri.parse('https://example.com/episode'),
            title: 'Episode',
          ),
          nextEpisode: next,
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();
    engine.endings.add(true);
    await tester.pump();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(NextEpisodeCountdown), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    expect(engine.stopped, isFalse);
    expect(find.byType(PlayerScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
