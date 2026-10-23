import 'package:iptv_flutter/presentation/channel_picker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/presentation/live_multiview_screen.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;

class AudioEngine extends FakeEngine implements AudioPlaybackEngine {
  final List<AudioEngine> all;
  final events = StreamController<bool>.broadcast();
  @override
  Stream<bool> get playing => events.stream;
  @override
  Stream<Duration> get position => const Stream.empty();
  int opens = 0;
  bool connected = false, disposed = false;
  double volume = 100;
  final VoidCallback onOpen;
  AudioEngine(this.all, this.onOpen);
  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> open(PlaybackSource source) async {
    opens++;
    connected = true;
    onOpen();
    events.add(true);
  }

  @override
  Future<void> stop() async {
    connected = false;
    events.add(false);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    connected = false;
    await events.close();
  }
}

const one = ContentItem(id: '1', name: 'Channel One', type: ContentType.live);
const two = ContentItem(id: '2', name: 'Channel Two', type: ContentType.live);
PlaybackSource stream(ContentItem channel) => PlaybackSource(
  uri: Uri.parse('https://example.com/${channel.id}'),
  title: channel.name,
  isLive: true,
);
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'two channels play side by side with exclusive audio and clean return to single player',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engines = <AudioEngine>[];
      var maximumConnections = 0;
      AudioEngine create() {
        final engine = AudioEngine(engines, () {
          final active = engines.where((entry) => entry.connected).length;
          if (active > maximumConnections) maximumConnections = active;
        });
        engines.add(engine);
        return engine;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: stream(one),
            item: one,
            engineFactory: create,
            loadChannels: () async => [one, two],
            resolveChannel: (item) async => stream(item),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Split screen'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveMultiviewScreen), findsOneWidget);
      expect(engines, hasLength(3));
      expect(engines[0].connected, isFalse);
      expect(engines[1].connected, isTrue);
      expect(engines[1].volume, 100);
      await tester.tap(find.byTooltip('Channels - Screen 2'));
      await tester.pumpAndSettle();
      final pickerBounds = tester.getRect(find.byType(ChannelPicker));
      expect(pickerBounds.left, greaterThanOrEqualTo(640));
      expect(pickerBounds.right, lessThanOrEqualTo(1280));
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Channel Two'));
      await tester.pumpAndSettle();
      expect(engines[2].connected, isTrue);
      expect(engines[2].volume, 0);
      await tester.tap(find.byTooltip('Audio - Screen 2'));
      await tester.pumpAndSettle();
      expect(engines[1].volume, 0);
      expect(engines[2].volume, 100);
      await tester.tap(find.byTooltip('Mute both screens'));
      await tester.pumpAndSettle();
      expect(engines[1].volume, 0);
      expect(engines[2].volume, 0);
      await tester.tap(find.byTooltip('Unmute audio'));
      await tester.pumpAndSettle();
      expect(engines[1].volume, 0);
      expect(engines[2].volume, 100);
      await tester.tap(find.byTooltip('Mute both screens'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Audio - Screen 1'));
      await tester.pumpAndSettle();
      expect(engines[1].volume, 100);
      expect(engines[2].volume, 0);
      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(LiveMultiviewScreen), findsNothing);
      expect(engines[1].disposed, isTrue);
      expect(engines[2].disposed, isTrue);
      expect(engines[0].connected, isTrue);
      expect(engines[0].opens, 2);
      expect(maximumConnections, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
