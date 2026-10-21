import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/data/video_recordings.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/recordings_library_screen.dart';
import 'profiles_locks_test.dart' show CatalogFixture;
import 'recordings_test.dart' show FileEngine, UiRecordingStore;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'Live TV records a channel to its profile library with saved status',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'streamora-live-recording-',
      );
      final store = UiRecordingStore(root);
      VideoRecordings.attach('record-ui', store);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'News',
              isLive: true,
            ),
            item: const ContentItem(
              id: '1',
              name: 'News',
              type: ContentType.live,
            ),
            history: WatchHistory('record-ui'),
            engineFactory: () => FileEngine(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> press(String tooltip) async {
        await tester.runAsync(() async {
          final button = tester.widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == tooltip,
            ),
          );
          await (button.onPressed as Future<void> Function())();
        });
        await tester.pumpAndSettle();
      }

      await press('Record');
      expect(find.text('Recording in progress'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      await press('Stop recording');
      expect(store.entries.single.item.type, ContentType.live);
      expect(store.entries.single.title, 'News');
      expect(find.text('Recording saved.'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(PlayerScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
  testWidgets('Live TV categories expose the Live TV recording library', (
    tester,
  ) async {
    final provider = CatalogFixture();
    final root = Directory.systemTemp.createTempSync('streamora-live-library-');
    final store = UiRecordingStore(root);
    VideoRecordings.attach(WatchHistory.forProvider(provider).scope, store);
    await tester.pumpWidget(
      MaterialApp(
        home: BrowseScreen(provider: provider, type: ContentType.live),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recordings'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordingsLibraryScreen), findsOneWidget);
    expect(find.text('Live TV recordings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
