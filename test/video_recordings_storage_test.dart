import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/video_recordings.dart';
import 'package:iptv_flutter/application/video_recorder.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/data/locked_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/video_recording_engine.dart';
import 'profiles_locks_test.dart' show CatalogFixture;

class FileRecorder implements VideoRecordingEngine {
  File? output;
  bool fail = false;
  @override
  Future<void> startVideoRecording(String path) async {
    output = File(path);
    await output!.writeAsBytes(List.filled(fail ? 0 : 4096, 1));
  }

  @override
  Future<void> stopVideoRecording() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('streamora-recording-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  const movie = ContentItem(
    id: '42',
    name: 'Movie',
    type: ContentType.movies,
    categoryId: '7',
  );
  test('recording writes a real file and survives storage reload', () async {
    final store = VideoRecordings('alice', rootOverride: root);
    final recorder = VideoRecorder(
      engine: FileRecorder(),
      store: store,
      item: movie,
      title: movie.name,
    );
    await recorder.toggle();
    expect(recorder.recording, isTrue);
    await recorder.toggle();
    expect(recorder.recording, isFalse);
    expect(store.entries.single.bytes, 4096);
    expect(await (await store.file(store.entries.single.id)).exists(), isTrue);
    final reloaded = VideoRecordings('alice', rootOverride: root);
    await reloaded.load();
    expect(reloaded.entries.single.title, movie.name);
    recorder.dispose();
  });
  test(
    'deleting one profile recordings preserves the other profile files',
    () async {
      final a = VideoRecordings('alice', rootOverride: root);
      final b = VideoRecordings('bob', rootOverride: root);
      for (final store in [a, b]) {
        final recorder = VideoRecorder(
          engine: FileRecorder(),
          store: store,
          item: movie,
          title: movie.name,
        );
        await recorder.toggle();
        await recorder.close();
        recorder.dispose();
      }
      final other = await b.file(b.entries.single.id);
      await a.deleteAll();
      expect(a.entries, isEmpty);
      expect(await other.exists(), isTrue);
      expect(b.entries, hasLength(1));
    },
  );
  test('empty capture is rejected without a saved success entry', () async {
    final store = VideoRecordings('alice', rootOverride: root);
    final recorder = VideoRecorder(
      engine: FileRecorder()..fail = true,
      store: store,
      item: movie,
      title: movie.name,
    );
    await recorder.toggle();
    await expectLater(recorder.toggle(), throwsA(isA<FileSystemException>()));
    expect(store.entries, isEmpty);
    expect(store.active, isEmpty);
    recorder.dispose();
  });
  test(
    'clearing history preserves file recordings and resume positions',
    () async {
      final store = VideoRecordings('alice', rootOverride: root);
      final recorder = VideoRecorder(
        engine: FileRecorder(),
        store: store,
        item: movie,
        title: movie.name,
      );
      await recorder.toggle();
      await recorder.close();
      final history = WatchHistory('alice');
      final entry = WatchEntry(
        movie,
        null,
        const Duration(minutes: 2),
        const Duration(minutes: 10),
        DateTime.now(),
      );
      await history.save(entry);
      await history.clear();
      expect(await history.entries(), isEmpty);
      expect(
        (await history.latest(movie))?.position,
        const Duration(minutes: 2),
      );
      expect(
        await (await store.file(store.entries.single.id)).exists(),
        isTrue,
      );
      recorder.dispose();
    },
  );
  test('recording file access cannot escape its profile directory', () async {
    final store = VideoRecordings('alice', rootOverride: root);
    await expectLater(store.file('../bob/other'), throwsFormatException);
  });
  test(
    'title PIN rules persist and protect direct provider playback',
    () async {
      final locks = CategoryLocks('alice');
      await locks.setPassword('123456');
      await locks.setTitleLocked(movie, true);
      final reloaded = CategoryLocks('alice');
      await reloaded.load();
      expect(reloaded.titleLocked(movie), isTrue);
      final provider = LockedProvider(CatalogFixture(), reloaded);
      await expectLater(
        provider.resolvePlayback(movie),
        throwsA(isA<ProviderException>()),
      );
      expect(reloaded.unlockTitle(movie, 'wrong'), isFalse);
      expect(reloaded.unlockTitle(movie, '123456'), isTrue);
      expect((await provider.resolvePlayback(movie)).uri.scheme, isNotEmpty);
      final other = CategoryLocks('bob');
      await other.load();
      expect(other.titleLocked(movie), isFalse);
      provider.dispose();
    },
  );
  test(
    'hidden categories are absent in categories, searches and direct access',
    () async {
      final locks = CategoryLocks('alice');
      await locks.load();
      const category = Category('7', 'English', ContentType.movies);
      await locks.setHidden(category, true);
      final provider = LockedProvider(CatalogFixture(), locks);
      expect(
        (await provider.getCategories(ContentType.movies)).map((e) => e.id),
        ['9'],
      );
      expect(
        (await provider.getAllItems(ContentType.movies)).map((e) => e.id),
        ['88'],
      );
      await expectLater(
        provider.resolvePlayback(movie),
        throwsA(isA<ProviderException>()),
      );
      await locks.setHidden(category, false);
      expect(await provider.getCategories(ContentType.movies), hasLength(2));
      provider.dispose();
    },
  );
}
