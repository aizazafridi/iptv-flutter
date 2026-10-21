import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/data/video_recordings.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/category_lock_settings_screen.dart';
import 'package:iptv_flutter/presentation/title_lock_settings_screen.dart';
import 'package:iptv_flutter/presentation/recordings_library_screen.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'profiles_locks_test.dart' show CatalogFixture;
import 'provider_test.dart' show FixtureClient;
import 'subtitle_test.dart' show FakeEngine;

class MemoryRecordings extends VideoRecordings {
  MemoryRecordings(super.scope);
  @override
  Future<void> load() async {}
  @override
  Future<void> delete(VideoRecording entry) async {
    entries.remove(entry);
    notifyListeners();
  }
}

class WarningEngine extends FakeEngine {
  final progress = StreamController<Duration>.broadcast();
  final warnings = StreamController<String>.broadcast();
  @override
  Stream<Duration> get position => progress.stream;
  @override
  Stream<String> get errors => warnings.stream;
  @override
  Future<void> dispose() async {
    await progress.close();
    await warnings.close();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'incomplete live entries do not prevent valid channels loading',
    () async {
      final client = FixtureClient()
        ..fixture = [
          null,
          {'name': 'Separator'},
          {'stream_id': 12},
          {'stream_id': 13, 'name': 'News'},
        ];
      final provider = XtreamProvider(client);
      final rows = await provider.getAllItems(ContentType.live);
      expect(rows.map((row) => row.id), ['12', '13']);
      expect(rows.first.name, isNotEmpty);
      expect(rows.last.name, 'News');
      provider.dispose();
    },
  );
  testWidgets(
    'category hiding and protection reuse the configured PIN without dialogs',
    (tester) async {
      final provider = CatalogFixture();
      final locks = CategoryLocks('parental-ui');
      CategoryLocks.attach(provider, locks);
      await locks.setPassword('123456');
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryLockSettingsScreen(
            provider: provider,
            type: ContentType.movies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final switches = find.byType(Switch);
      await tester.tap(switches.at(0));
      await tester.pumpAndSettle();
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      const category = Category('7', '', ContentType.movies);
      expect(locks.hidden(category), isTrue);
      expect(locks.configured(category), isTrue);
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      expect(locks.configured(category), isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: TitleLockSettingsScreen(
            provider: provider,
            type: ContentType.movies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(
        locks.titleConfigured(
          const ContentItem(
            id: '42',
            name: 'Locked title',
            type: ContentType.movies,
          ),
        ),
        isTrue,
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets('remote Right focuses recording deletion and Enter deletes', (
    tester,
  ) async {
    final provider = CatalogFixture();
    final store = MemoryRecordings(WatchHistory.forProvider(provider).scope);
    store.entries = [
      VideoRecording(
        id: 'a',
        title: 'Saved movie',
        item: const ContentItem(
          id: '42',
          name: 'Movie',
          type: ContentType.movies,
        ),
        created: DateTime.now(),
        durationMs: 10000,
        bytes: 4096,
      ),
    ];
    VideoRecordings.attach(store.scope, store);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordingsLibraryScreen(
          provider: provider,
          type: ContentType.movies,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final delete = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton && widget.tooltip == 'Delete recording',
      ),
    );
    expect(delete.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.entries, isEmpty);
    expect(find.text('No saved recordings for this account.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  testWidgets(
    'movie playback progress suppresses warnings and a stalled error is shown',
    (tester) async {
      final engine = WarningEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Live',
              isLive: false,
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.warnings.add('Stream failed');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      engine.progress.add(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Stream failed'), findsNothing);
      engine.warnings.add('Stream failed');
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Stream failed'), findsOneWidget);
      engine.progress.add(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      expect(find.text('Stream failed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
