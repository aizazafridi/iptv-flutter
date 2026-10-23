import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/last_live_channel.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test('last live channel persists per profile and ignores movies', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = LastLiveChannel('one');
    expect(await store.load(), isNull);
    await store.save(
      const ContentItem(
        id: '42',
        name: 'Last channel',
        type: ContentType.live,
        categoryId: '7',
      ),
    );
    await store.save(
      const ContentItem(id: '99', name: 'Movie', type: ContentType.movies),
    );
    final restored = await LastLiveChannel('one').load();
    expect(restored?.id, '42');
    expect(restored?.categoryId, '7');
    expect(await LastLiveChannel('two').load(), isNull);
  });
}
