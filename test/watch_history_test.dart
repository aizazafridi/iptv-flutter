import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test(
    'clearing movie history preserves series progress in the same account',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final history = WatchHistory('selective');
      const movie = ContentItem(
        id: '1',
        name: 'Movie',
        type: ContentType.movies,
      );
      const series = ContentItem(
        id: '2',
        name: 'Series',
        type: ContentType.series,
      );
      for (final item in [movie, series]) {
        await history.save(
          WatchEntry(
            item,
            null,
            const Duration(minutes: 2),
            const Duration(minutes: 10),
            DateTime.utc(2026),
          ),
        );
      }
      await history.clear(type: ContentType.movies);
      final restored = WatchHistory('selective');
      expect(await restored.items(ContentType.movies), isEmpty);
      expect((await restored.items(ContentType.series)).single.id, '2');
      await restored.clear(type: ContentType.series);
      expect(await WatchHistory('selective').entries(), isEmpty);
    },
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'history persists progress, separates accounts and removes completed movies',
    () async {
      final history = WatchHistory('account-a');
      const movie = ContentItem(
        id: '42',
        name: 'Movie',
        type: ContentType.movies,
      );
      await history.save(
        WatchEntry(
          movie,
          null,
          const Duration(minutes: 4),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      final restored = WatchHistory('account-a');
      expect(
        (await restored.latest(movie))!.position,
        const Duration(minutes: 4),
      );
      expect((await restored.items(ContentType.movies)).single.id, '42');
      expect(await WatchHistory('account-b').entries(), isEmpty);
      await restored.save(
        WatchEntry(
          movie,
          null,
          const Duration(minutes: 10),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      expect(await restored.items(ContentType.movies), isEmpty);
    },
  );
  test(
    'series history retains the latest episode and positions per episode',
    () async {
      final history = WatchHistory('series-account');
      const series = ContentItem(
        id: '99',
        name: 'Series',
        type: ContentType.series,
      );
      const first = Episode(
        id: '1',
        title: 'First',
        season: 1,
        number: 1,
        extension: 'mp4',
      );
      const second = Episode(
        id: '2',
        title: 'Second',
        season: 2,
        number: 1,
        extension: 'mp4',
      );
      await history.save(
        WatchEntry(
          series,
          first,
          const Duration(minutes: 2),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      await history.save(
        WatchEntry(
          series,
          second,
          const Duration(minutes: 3),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      expect((await history.latest(series))!.episode!.id, '2');
      expect(
        (await history.latest(series, episode: first))!.position,
        const Duration(minutes: 2),
      );
      expect((await history.items(ContentType.series)).length, 1);
    },
  );
}
