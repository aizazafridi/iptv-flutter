import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'widget_test.dart' show FakeProvider;
import 'recordings_test.dart' show SegmentEngine;

const movie = ContentItem(
  id: 'watched',
  name: 'Just watched',
  type: ContentType.movies,
);
WatchEntry entry(int seconds, {int duration = 600}) => WatchEntry(
  movie,
  null,
  Duration(seconds: seconds),
  Duration(seconds: duration),
  DateTime.now(),
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'zero and unknown-duration events after clearing cannot erase saved resume',
    () async {
      final history = WatchHistory('account');
      await history.save(entry(120));
      await history.clear();
      await history.save(entry(0));
      await history.save(entry(0, duration: 0));
      expect(await history.entries(), isEmpty);
      expect(
        (await WatchHistory('account').latest(movie))!.position,
        const Duration(seconds: 120),
      );
    },
  );
  test(
    'reconnected providers share account state and clear cannot overwrite newer resume data',
    () async {
      final registry = ProviderRegistry()
        ..register('fixture', 'Fixture', (_) => FakeProvider());
      const config = ProviderConfig(
        providerId: 'fixture',
        server: 'https://example.com',
        username: 'a',
        password: 'b',
        profileId: 'profile',
      );
      final first = registry.create(config), second = registry.create(config);
      final watching = WatchHistory.forProvider(first),
          settings = WatchHistory.forProvider(second);
      expect(watching, same(settings));
      await watching.save(entry(120));
      await settings.clear();
      expect(await watching.entries(), isEmpty);
      expect(
        (await settings.latest(movie))!.position,
        const Duration(seconds: 120),
      );
      final stale = WatchHistory('profile');
      await stale.entries();
      await watching.save(entry(180));
      await stale.clear();
      expect(
        (await WatchHistory('profile').latest(movie))!.position,
        const Duration(seconds: 180),
      );
      first.dispose();
      second.dispose();
    },
  );
  test(
    'queued save and clear keep history cleared and retain resume on reload',
    () async {
      final history = WatchHistory('queue');
      await Future.wait([history.save(entry(120)), history.clear()]);
      final reload = WatchHistory('queue');
      expect(await reload.entries(), isEmpty);
      expect(
        (await reload.latest(movie))!.position,
        const Duration(seconds: 120),
      );
    },
  );
  testWidgets(
    'leaving playback before ten-second timer refreshes Continue Watching immediately',
    (tester) async {
      final provider = FakeProvider();
      final history = WatchHistory.forProvider(provider);
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(provider: provider, type: ContentType.movies),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue watching'));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final engine = SegmentEngine();
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: movie.name,
            ),
            engineFactory: () => engine,
            history: history,
            item: movie,
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.positions.add(const Duration(seconds: 120));
      await tester.pump();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text(movie.name), findsOneWidget);
      expect(
        (await history.latest(movie))!.position,
        const Duration(seconds: 120),
      );
      await history.clear();
      await tester.pumpAndSettle();
      expect(find.text(movie.name), findsNothing);
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => DetailsScreen(provider: provider, item: movie),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'an already open details page refreshes Resume when player progress changes',
    (tester) async {
      final provider = FakeProvider();
      final history = WatchHistory.forProvider(provider);
      await tester.pumpWidget(
        MaterialApp(
          home: DetailsScreen(provider: provider, item: movie),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Play'), findsOneWidget);
      await history.save(entry(120));
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      await history.clear();
      await tester.pumpAndSettle();
      expect(find.text('Resume'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
