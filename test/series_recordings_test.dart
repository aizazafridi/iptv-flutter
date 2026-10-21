import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/video_recordings.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test(
    'series episode recordings are separate files in the profile library',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'streamora-episodes-test-',
      );
      try {
        final store = VideoRecordings('account1', rootOverride: root);
        const item = ContentItem(
          id: 'show',
          name: 'Series',
          type: ContentType.series,
        );
        for (final title in ['Series - Pilot', 'Series - Next']) {
          final id = await store.reserve();
          await (await store.file(id)).writeAsBytes(List.filled(4096, 1));
          await store.finish(id, item, title, const Duration(seconds: 10));
        }
        final first = store.entries.first;
        final other = store.entries.last;
        await store.delete(first);
        expect(await (await store.file(first.id)).exists(), isFalse);
        expect(await (await store.file(other.id)).exists(), isTrue);
        final reloaded = VideoRecordings('account1', rootOverride: root);
        await reloaded.load();
        expect(reloaded.entries.single.title, 'Series - Pilot');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
