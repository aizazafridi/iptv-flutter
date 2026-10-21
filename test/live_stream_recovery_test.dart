import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/playback_engine.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'subtitle_test.dart' show FakeEngine;
import 'package:iptv_flutter/playback/live_stream_recovery.dart';

class RecoveryEngine extends FakeEngine implements CompletionPlaybackEngine {
  final frames = StreamController<Duration>.broadcast();
  final states = StreamController<bool>.broadcast();
  final endings = StreamController<bool>.broadcast();
  bool active = true;
  int opens = 0, pauses = 0;
  @override
  Stream<Duration> get position => frames.stream;
  @override
  Stream<bool> get playing => states.stream;
  @override
  Stream<bool> get completed => endings.stream;
  @override
  Future<void> open(PlaybackSource source) async {
    opens++;
    active = true;
    states.add(true);
  }

  @override
  Future<void> togglePause() async {
    pauses++;
    active = !active;
    states.add(active);
  }

  @override
  Future<void> dispose() async {
    await frames.close();
    await states.close();
    await endings.close();
  }
}

void main() {
  testWidgets(
    'live player reopens an ended stream and respects a manual pause',
    (tester) async {
      final engine = RecoveryEngine();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/live'),
              title: 'Channel',
              isLive: true,
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      engine.frames.add(const Duration(seconds: 1));
      await tester.pump();
      engine.endings.add(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(engine.opens, 2);
      expect(engine.pauses, 0);
      expect(find.text('Reconnecting channel...'), findsOneWidget);
      engine.frames.add(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      expect(find.text('Reconnecting channel...'), findsNothing);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(engine.pauses, 1);
      await tester.pump(const Duration(seconds: 60));
      expect(engine.opens, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
      expect(engine.opens, 2);
    },
  );
  testWidgets(
    'failure retries with backoff until actual progress confirms recovery',
    (tester) async {
      var opens = 0;
      final status = <bool>[];
      final recovery = LiveStreamRecovery(
        reconnect: () async {
          opens++;
        },
        onRecovering: status.add,
      );
      recovery.progress(const Duration(seconds: 1));
      recovery.failed();
      recovery.failed();
      await tester.pump(const Duration(seconds: 2));
      expect(opens, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(opens, 2);
      recovery.progress(const Duration(seconds: 2));
      expect(status, [true, false]);
      await tester.pump(const Duration(seconds: 8));
      expect(opens, 2);
      await recovery.close();
    },
  );
  testWidgets('intentional pause disables retries until the user resumes', (
    tester,
  ) async {
    var opens = 0;
    final recovery = LiveStreamRecovery(
      reconnect: () async {
        opens++;
      },
      onRecovering: (_) {},
    );
    recovery.failed();
    recovery.setPaused(true);
    await tester.pump(const Duration(seconds: 60));
    expect(opens, 0);
    recovery.failed();
    await tester.pump(const Duration(seconds: 60));
    expect(opens, 0);
    recovery.setPaused(false);
    recovery.failed();
    await tester.pump(const Duration(seconds: 2));
    expect(opens, 1);
    await recovery.close();
  });
  testWidgets(
    'stalled playback is reopened without an error or stopped event',
    (tester) async {
      var opens = 0;
      final recovery = LiveStreamRecovery(
        reconnect: () async {
          opens++;
        },
        onRecovering: (_) {},
      );
      recovery.progress(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 13));
      expect(opens, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(opens, 1);
      await recovery.close();
    },
  );
  testWidgets('reconnects never overlap and closing cancels pending work', (
    tester,
  ) async {
    var opens = 0;
    final pending = Completer<void>();
    final recovery = LiveStreamRecovery(
      reconnect: () {
        opens++;
        return pending.future;
      },
      onRecovering: (_) {},
    );
    recovery.failed();
    await tester.pump(const Duration(seconds: 2));
    expect(opens, 1);
    recovery.failed();
    await tester.pump(const Duration(seconds: 120));
    expect(opens, 1);
    final closed = recovery.close();
    pending.complete();
    await closed;
    await tester.pump(const Duration(seconds: 60));
    expect(opens, 1);
  });
  testWidgets(
    'a transient warning does not reconnect if stream progress continues',
    (tester) async {
      var opens = 0;
      final recovery = LiveStreamRecovery(
        reconnect: () async {
          opens++;
        },
        onRecovering: (_) {},
      );
      recovery.failed();
      await tester.pump(const Duration(seconds: 1));
      recovery.progress(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 2));
      expect(opens, 0);
      await recovery.close();
    },
  );
}
