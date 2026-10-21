import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/video_recordings.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/playback/video_recording_engine.dart';
import 'subtitle_test.dart' show FakeEngine;

class SegmentEngine extends FakeEngine {
  final positions = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    positions.add(position);
  }

  @override
  Future<void> dispose() async {
    await positions.close();
  }
}

class FileEngine extends FakeEngine implements VideoRecordingEngine {
  @override
  Future<void> startVideoRecording(String path) async {
    File(path).writeAsBytesSync(List.filled(4096, 1));
  }

  @override
  Future<void> stopVideoRecording() async {}
}

class UiRecordingStore extends VideoRecordings {
  final Directory root;
  UiRecordingStore(this.root) : super('record-ui');
  @override
  Future<void> load() async {}
  @override
  Future<String> reserve() async {
    active.add('fixture');
    return 'fixture';
  }

  @override
  Future<File> file(String id) async => File('${root.path}/$id.mkv');
  @override
  Future<void> finish(
    String id,
    ContentItem item,
    String title,
    Duration duration,
  ) async {
    entries = [
      VideoRecording(
        id: id,
        title: title,
        item: item,
        created: DateTime.now(),
        durationMs: duration.inMilliseconds,
        bytes: 4096,
      ),
    ];
    active.remove(id);
    notifyListeners();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'Record writes a profile file, shows status and saves; library control is absent',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'streamora-player-test-',
      );
      final store = UiRecordingStore(root);
      VideoRecordings.attach('record-ui', store);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: 'Movie',
            ),
            engineFactory: () => FileEngine(),
            history: WatchHistory('record-ui'),
            item: const ContentItem(
              id: '42',
              name: 'Movie',
              type: ContentType.movies,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(
        tester
            .widget<PopupMenuButton<double>>(
              find.byType(PopupMenuButton<double>),
            )
            .enabled,
        isTrue,
      );
      expect(find.byTooltip('Recordings'), findsNothing);
      await tester.runAsync(() async {
        await (tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton && widget.tooltip == 'Record',
                  ),
                )
                .onPressed
            as Future<void> Function())();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Recording in progress'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(
        tester
            .widget<PopupMenuButton<double>>(
              find.byType(PopupMenuButton<double>),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
            .enabled,
        isFalse,
      );
      for (final direction in ['Rewind', 'Forward']) {
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is IconButton &&
                      (widget.tooltip ?? '').startsWith(direction),
                ),
              )
              .onPressed,
          isNull,
        );
      }

      await tester.runAsync(() async {
        await (tester
                .widget<IconButton>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is IconButton &&
                        widget.tooltip == 'Stop recording',
                  ),
                )
                .onPressed
            as Future<void> Function())();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.text('Recording saved.'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
      expect(
        tester
            .widget<PopupMenuButton<double>>(
              find.byType(PopupMenuButton<double>),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
            .enabled,
        isTrue,
      );

      expect(find.text('Recording in progress'), findsNothing);
      expect(store.entries, hasLength(1));
      ScaffoldMessenger.of(
        tester.element(find.byType(PlayerScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await root.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'Live TV without a profile or channel does not expose recording',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Live',
              isLive: true,
            ),
            engineFactory: () => FileEngine(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Record'), findsNothing);
      expect(find.byTooltip('Recordings'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
