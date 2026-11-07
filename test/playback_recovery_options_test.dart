import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/live_stream_recovery.dart';
import 'package:iptv_flutter/playback/playback_diagnostics.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'live_stream_recovery_test.dart' show RecoveryEngine;
import 'provider_test.dart' show FixtureClient;
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';

class DiagnosticEngine extends RecoveryEngine
    implements DiagnosticPlaybackEngine, QualityPlaybackEngine {
  final failures = StreamController<String>.broadcast();
  final sources = <PlaybackSource>[];
  bool hasQualities = false;
  String qualitySelected = 'high';
  @override
  Stream<String> get errors => failures.stream;
  @override
  Future<void> open(PlaybackSource source) async {
    sources.add(source);
    await super.open(source);
  }

  @override
  Future<PlaybackDiagnostics> readDiagnostics() async =>
      const PlaybackDiagnostics(
        videoCodec: 'h264',
        audioCodec: 'aac',
        width: 1920,
        height: 1080,
        bufferSeconds: 4,
        fps: 25,
      );
  @override
  List<PlaybackQuality> get videoQualities => hasQualities
      ? [
          const PlaybackQuality('low', '720p', height: 720),
          const PlaybackQuality('high', '1080p', height: 1080),
        ]
      : [];
  @override
  String get selectedVideoQuality => qualitySelected;
  @override
  Future<void> selectVideoQuality(String id) async {
    qualitySelected = id;
  }

  @override
  Future<void> dispose() async {
    await failures.close();
    await super.dispose();
  }
}

void main() {
  test(
    'connection diagnostics redact credentials and retain useful error categories',
    () {
      for (final entry in {
        'HTTP error 403 https://user:secret@example.com/live/user/password/1.ts?token=private':
            'HTTP 403',
        'Connection timed out for https://host/user/secret': 'timed out',
        'Could not resolve https://host/token': 'resolve',
        'decoder failed https://user:secret@example.com': 'codec',
      }.entries) {
        final result = PlaybackFailure.from(entry.key);
        expect(result.message, contains(entry.value));
        expect(result.message, isNot(contains('secret')));
        expect(result.message, isNot(contains('https://')));
        expect(result.message, isNot(contains('private')));
      }
      expect(PlaybackFailure.from('HTTP 401 unauthorized').retryable, isFalse);
      expect(PlaybackFailure.from('HTTP 503 unavailable').retryable, isTrue);
      final tls = PlaybackFailure.from('TLS certificate failed');
      expect(PlaybackFailure.from(tls.message).retryable, isFalse);
    },
  );
  testWidgets(
    'recovery stops after three attempts and never loops indefinitely',
    (tester) async {
      var opens = 0, exhausted = 0;
      final recovery = LiveStreamRecovery(
        reconnect: () async {
          opens++;
        },
        onRecovering: (_) {},
        onExhausted: () => exhausted++,
      );
      recovery.failed();
      for (final delay in [2, 4, 8]) {
        await tester.pump(Duration(seconds: delay));
        await tester.pump(const Duration(seconds: 30));
      }
      expect(opens, 3);
      expect(exhausted, 1);
      expect(recovery.exhausted, isTrue);
      await tester.pump(const Duration(minutes: 10));
      recovery.failed();
      await tester.pump(const Duration(seconds: 60));
      expect(opens, 3);
      await recovery.close();
    },
  );
  testWidgets(
    'available video timestamps detect frozen video despite advancing audio',
    (tester) async {
      var opens = 0;
      final recovery = LiveStreamRecovery(
        reconnect: () async {
          opens++;
        },
        onRecovering: (_) {},
      );
      recovery.videoProgress(const Duration(seconds: 1));
      for (var i = 1; i <= 17; i++) {
        recovery.progress(Duration(seconds: i * 2));
        recovery.videoProgress(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 2));
      }
      expect(opens, 1);
      await recovery.close();
    },
  );
  test(
    'Xtream exposes explicit backup URLs and never guesses quality URLs',
    () async {
      final client = FixtureClient()
        ..fixture = [
          {
            'stream_id': '1',
            'name': 'Channel',
            'direct_source': 'https://backup.example.com/provider.ts',
          },
          {'stream_id': '2', 'name': 'Channel HD'},
        ];
      final provider = XtreamProvider(client);
      final rows = await provider.getAllItems(ContentType.live);
      final first = await provider.resolvePlayback(rows.first);
      expect(first.alternatives.single.source.uri.host, 'backup.example.com');
      expect((await provider.resolvePlayback(rows.last)).alternatives, isEmpty);
      provider.dispose();
    },
  );
  for (final supplied in [false, true]) {
    testWidgets(
      'recovery choices use only supplied alternatives and quality tracks: $supplied',
      (tester) async {
        final engine = DiagnosticEngine()..hasQualities = supplied;
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              source: PlaybackSource(
                uri: Uri.parse('https://example.com/primary'),
                title: 'Channel',
                isLive: true,
                alternatives: supplied
                    ? [
                        PlaybackAlternative(
                          'Provider backup',
                          PlaybackSource(
                            uri: Uri.parse('https://example.com/backup'),
                            title: 'Channel',
                            isLive: true,
                          ),
                        ),
                      ]
                    : [],
              ),
              engineFactory: () => engine,
            ),
          ),
        );
        await tester.pumpAndSettle();
        engine.failures.add(
          'HTTP 403 https://user:password@example.com/private',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('access denied'), findsOneWidget);
        expect(find.textContaining('password'), findsNothing);
        expect(find.text('Retry playback'), findsOneWidget);
        expect(
          find.text('Try alternate stream / quality'),
          supplied ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Diagnostics'));
        await tester.pumpAndSettle();
        expect(find.textContaining('h264'), findsOneWidget);
        expect(find.textContaining('1920 x 1080'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        if (supplied) {
          await tester.tap(find.text('Try alternate stream / quality'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('720p'));
          await tester.pumpAndSettle();
          expect(engine.qualitySelected, 'low');
          expect(engine.opens, 1);
          engine.failures.add('HTTP 403 denied');
          await tester.pumpAndSettle();
          await tester.tap(find.text('Try alternate stream / quality'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Provider backup'));
          await tester.pumpAndSettle();
          expect(engine.sources.last.uri.path, '/backup');
          expect(engine.opens, 2);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
