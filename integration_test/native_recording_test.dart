import 'dart:io';
import 'dart:math';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_https/ffmpeg_kit_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/media_kit_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final dll = File('build/windows/x64/runner/Debug/libmpv-2.dll');
  for (final live in [false, true]) {
    test(
      'native ${live ? 'live' : 'VOD'} recording creates independently playable media',
      () async {
        MediaKit.ensureInitialized();
        final root = await Directory.systemTemp.createTemp(
          'streamora-native-test-',
        );
        await FFmpegKitConfig.disableLogs();
        final fixture = '${root.path}/fixture.mkv';
        final generation = await FFmpegKit.executeWithArguments([
          '-f',
          'lavfi',
          '-i',
          'testsrc=size=128x72:rate=15',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=16000',
          '-t',
          '12',
          '-c:v',
          'mpeg4',
          '-c:a',
          'aac',
          '-y',
          fixture,
        ]);
        expect((await generation.getReturnCode())?.getValue(), 0);
        final bytes = await File(fixture).readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          try {
            request.response.headers.set('Content-Type', 'video/x-matroska');
            request.response.contentLength = bytes.length;
            for (var i = 0; i < bytes.length; i += 3200) {
              request.response.add(
                bytes.sublist(i, min(i + 3200, bytes.length)),
              );
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            await request.response.close();
          } catch (_) {
            /* The recorder can stop before the fixture stream finishes. */
          }
        });
        final engine = MediaKitEngine();
        final errors = <String>[];
        final errorSubscription = engine.errors.listen(errors.add);
        Player? verifier;
        try {
          await engine.open(
            PlaybackSource(
              uri: Uri.parse('http://127.0.0.1:${server.port}/sample.wav'),
              title: 'Recording test',
              isLive: live,
            ),
          );
          final path = '${root.path}/capture.mkv';
          await engine.startVideoRecording(path);
          await Future<void>.delayed(const Duration(seconds: 3));
          await engine.stopVideoRecording();
          expect(await File(path).exists(), isTrue, reason: errors.join(' | '));
          expect(await File(path).length(), greaterThan(1024));
          verifier = Player();
          final duration = verifier.stream.duration.firstWhere(
            (value) => value > Duration.zero,
          );
          await verifier.open(Media(Uri.file(path).toString()), play: false);
          expect(
            await duration.timeout(const Duration(seconds: 8)),
            greaterThan(Duration.zero),
          );
          expect(
            verifier.state.tracks.video.where(
              (track) => track.id != 'auto' && track.id != 'no',
            ),
            isNotEmpty,
          );
        } finally {
          await errorSubscription.cancel();
          await verifier?.dispose();
          await engine.dispose();
          await server.close(force: true);
          await root.delete(recursive: true);
        }
      },
      skip: !Platform.isWindows || !dll.existsSync(),
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
