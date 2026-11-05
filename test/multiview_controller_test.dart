import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/multiview_controller.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'live_multiview_test.dart' show AudioEngine;

ContentItem channel(int i) =>
    ContentItem(id: '$i', name: 'Channel $i', type: ContentType.live);
PlaybackSource source(ContentItem item) => PlaybackSource(
  uri: Uri.parse('https://example.com/${item.id}'),
  title: item.name,
  isLive: true,
  headers: const {'X-Test': 'preserved'},
);
void main() {
  test(
    'lazy sessions, four layouts, swaps, audio, expand and lifecycle release owned engines',
    () async {
      final engines = <AudioEngine>[];
      final controller = MultiViewController(
        createEngine: () {
          final e = AudioEngine(engines, () {});
          engines.add(e);
          return e;
        },
        resolve: (item) async => source(item),
      );
      await controller.initialize(source(channel(1)), channel(1));
      expect(engines.length, 1);
      await controller.assign(1, channel(2));
      await controller.setLayout(4);
      expect(engines.length, 2);
      await Future.wait([
        controller.assign(2, channel(3)),
        controller.assign(3, channel(4)),
      ]);
      expect(engines.length, 4);
      await controller.listenTo(3);
      expect(engines.map((e) => e.volume), [0, 0, 0, 100]);
      await controller.swap(0, 3);
      expect(controller.panels.first.channel!.id, '4');
      expect(engines.every((e) => e.opens == 1), isTrue);
      expect(controller.audioId, 3);
      await controller.setLayout(2);
      expect(engines[0].disposed, isTrue);
      expect(engines[2].disposed, isTrue);
      expect(engines[1].disposed, isFalse);
      expect(engines[3].disposed, isFalse);
      await controller.expand(1);
      expect(engines[3].disposed, isTrue);
      expect(engines[1].opens, 1);
      await controller.collapse();
      expect(engines.length, 5);
      expect(engines[1].opens, 1);
      await controller.lifecycle(true);
      expect(engines.every((e) => e.disposed), isTrue);
      await controller.lifecycle(false);
      expect(engines.where((e) => e.connected).length, 2);
      await controller.shutdown();
      controller.dispose();
      expect(engines.every((e) => e.disposed), isTrue);
    },
  );
  test(
    'one decoder failure releases only that panel and explicit retry resolves again',
    () async {
      final engines = <AudioEngine>[];
      var resolutions = 0;
      final controller = MultiViewController(
        createEngine: () {
          final e = AudioEngine(engines, () {});
          engines.add(e);
          return e;
        },
        resolve: (item) async {
          resolutions++;
          return source(item);
        },
      );
      await controller.initialize(source(channel(1)), channel(1));
      await controller.assign(1, channel(2));
      engines[1].failures.add('Decoder unavailable');
      await Future<void>.delayed(Duration.zero);
      await controller.setFit('Original');
      expect(engines[0].connected, isTrue);
      expect(engines[0].opens, 1);
      expect(engines[1].disposed, isTrue);
      expect(controller.panels[1].error, contains('playback limit'));
      await controller.retry(1);
      expect(resolutions, 2);
      expect(engines.length, 3);
      expect(engines.last.connected, isTrue);
      expect(engines.last.sources.single.headers, {'X-Test': 'preserved'});
      await controller.shutdown();
      controller.dispose();
    },
  );
  test(
    'provider limit prevents extra streams and failed resolution preserves playback',
    () async {
      final engines = <AudioEngine>[];
      final controller = MultiViewController(
        maxStreams: 1,
        createEngine: () {
          final e = AudioEngine(engines, () {});
          engines.add(e);
          return e;
        },
        resolve: (item) async {
          if (item.id == 'bad') throw StateError('Unavailable');
          return source(item);
        },
      );
      await controller.initialize(source(channel(1)), channel(1));
      await controller.assign(1, channel(2));
      expect(engines.length, 1);
      expect(controller.warning, contains('provider allows 1'));
      await controller.assign(
        0,
        const ContentItem(id: 'bad', name: 'Bad', type: ContentType.live),
      );
      expect(engines.first.disposed, isFalse);
      expect(controller.panels.first.channel!.id, '1');
      await controller.shutdown();
      controller.dispose();
    },
  );
  test(
    'background and shutdown unblock readiness wait without an abandoned session',
    () async {
      final engines = <AudioEngine>[];
      final controller = MultiViewController(
        createEngine: () {
          final e = AudioEngine(engines, () {});
          engines.add(e);
          return e;
        },
        resolve: (item) async => source(item),
      );
      await controller.initialize(source(channel(1)), channel(1));
      await controller.setLayout(3);
      await controller.assign(2, channel(3));
      await controller.remove(0);
      expect(controller.audioId, 2);
      expect(engines.last.volume, 100);
      await controller.shutdown();
      controller.dispose();
    },
  );
}
