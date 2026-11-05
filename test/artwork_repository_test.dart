import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/data/artwork_repository.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/presentation/shared_artwork_image.dart';

class BytesService extends FileService {
  int calls = 0;
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return BytesResponse();
  }
}

class BytesResponse implements FileServiceResponse {
  @override
  Stream<List<int>> get content => Stream.value(List.filled(1024, 42));
  @override
  int get contentLength => 1024;
  @override
  int get statusCode => 200;
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
  @override
  String? get eTag => 'test';
  @override
  String get fileExtension => '.jpg';
}

class ControlledClient extends http.BaseClient {
  final streams = <StreamController<List<int>>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stream = StreamController<List<int>>();
    streams.add(stream);
    return http.StreamedResponse(
      stream.stream,
      200,
      headers: {'content-type': 'image/jpeg', 'cache-control': 'max-age=3600'},
    );
  }

  @override
  void close() {}
}

class AbortClient extends http.BaseClient {
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await (request as http.Abortable).abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'queue starts four foreground downloads and one background, joins identical requests',
    () async {
      final queue = ArtworkQueue();
      final hold = Completer<void>();
      var fg = 0, bg = 0, duplicate = 0;
      final work = <Future<void>>[];
      for (var i = 0; i < 8; i++) {
        work.add(
          queue.run('f$i', () async {
            fg++;
            await hold.future;
          }, priority: () => ArtworkPriority.visible),
        );
      }
      for (var i = 0; i < 4; i++) {
        work.add(
          queue.run('b$i', () async {
            bg++;
            await hold.future;
          }, priority: () => ArtworkPriority.nearVisible),
        );
      }
      work.add(
        queue.run('f0', () async {
          duplicate++;
        }, priority: () => ArtworkPriority.visible),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fg, 4);
      expect(bg, 1);
      expect(duplicate, 0);
      hold.complete();
      await Future.wait(work);
      expect(fg, 8);
      expect(bg, 4);
      expect(duplicate, 0);
    },
  );
  test(
    'obsolete queued jobs are cancelled and visible work overtakes cast work',
    () async {
      final queue = ArtworkQueue(foregroundLimit: 1, backgroundLimit: 1);
      final hold = Completer<void>();
      final events = <String>[];
      final first = queue.run(
        'first',
        () => hold.future,
        priority: () => ArtworkPriority.cast,
      );
      await Future<void>.delayed(Duration.zero);
      var wanted = true;
      final stale = queue.run(
        'stale',
        () async {
          events.add('stale');
        },
        priority: () => ArtworkPriority.nearVisible,
        wanted: () => wanted,
      );
      final cancelled = expectLater(stale, throwsA(isA<ArtworkCancelled>()));
      final cast = queue.run('cast', () async {
        events.add('cast');
      }, priority: () => ArtworkPriority.cast);
      final visible = queue.run('visible', () async {
        events.add('visible');
      }, priority: () => ArtworkPriority.visible);
      wanted = false;
      queue.drain();
      await visible;
      expect(events, ['visible']);
      hold.complete();
      await Future.wait([first, cast, cancelled]);
      expect(events, ['visible', 'cast']);
    },
  );
  test(
    'CDN variants change only allowlisted public TMDB paths; signed provider identity stays intact',
    () {
      const image = 'https://image.tmdb.org/t/p/original/poster.jpg';
      expect(
        ArtworkRepository.variant(image, ArtworkKind.poster),
        contains('/w185/'),
      );
      expect(
        ArtworkRepository.variant(image, ArtworkKind.episode),
        contains('/w300/'),
      );
      const signed = 'https://provider.test/poster.jpg?username=a&token=secret';
      expect(ArtworkRepository.variant(signed, ArtworkKind.poster), signed);
      expect(
        ArtworkRepository.cacheKey(signed),
        isNot(
          ArtworkRepository.cacheKey(signed.replaceFirst('secret', 'other')),
        ),
      );
      ArtworkMetrics.enabled = true;
      ArtworkMetrics.events.clear();
      ArtworkMetrics.record('test', url: signed);
      expect(
        ArtworkMetrics.events.single.toString(),
        isNot(contains('secret')),
      );
      expect(
        ArtworkMetrics.events.single.toString(),
        isNot(contains('username')),
      );
      ArtworkMetrics.enabled = false;
    },
  );
  test(
    'existing disk cache coalesces downloads, serves warm files and separates signed URLs',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'streamora-artwork-test-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );
      final service = BytesService();
      final repository = ArtworkRepository.forTesting(
        Config('artwork-unit', fileService: service),
      );
      const url = 'https://provider.test/poster.jpg?profile=a';
      final rows = await Future.wait([
        repository.getSingleFile(url),
        repository.getSingleFile(url),
      ]);
      expect(service.calls, 1);
      expect(await rows.first.length(), 1024);
      await repository.getSingleFile(url);
      expect(service.calls, 1);
      await repository.getSingleFile(
        url.replaceFirst('profile=a', 'profile=b'),
      );
      expect(service.calls, 2);
      await repository.dispose();
      final restored = ArtworkRepository.forTesting(
        Config('artwork-unit', fileService: service),
      );
      await restored.getSingleFile(url);
      expect(service.calls, 2);
      await restored.emptyCache();
      await restored.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await dir.delete(recursive: true);
    },
  );
  test(
    'HTTP queue slot stays occupied until body completes, then admits next request',
    () async {
      final client = ControlledClient();
      final service = ArtworkHttpFileService(client: client);
      final owner = Object();
      final urls = List.generate(5, (i) => 'https://provider.test/image$i.jpg');
      for (final url in urls) {
        ArtworkRepository.demand(url, owner, ArtworkPriority.visible);
      }
      final responses = urls.map((url) => service.get(url)).toList();
      await Future<void>.delayed(Duration.zero);
      expect(client.streams.length, 4);
      final first = await responses.first;
      final firstBody = first.content.drain<void>();
      client.streams.first.add([1, 2, 3]);
      await client.streams.first.close();
      await firstBody;
      await Future<void>.delayed(Duration.zero);
      expect(client.streams.length, 5);
      final done = <Future<void>>[];
      for (var i = 1; i < 5; i++) {
        done.add((await responses[i]).content.drain<void>());
      }
      for (final stream in client.streams.skip(1)) {
        await stream.close();
      }
      await Future.wait(done);
      for (final url in urls) {
        ArtworkRepository.release(url, owner);
      }
    },
  );
  test(
    'deadline aborts the HTTP request instead of leaving a competing download alive',
    () async {
      final client = AbortClient();
      final service = ArtworkHttpFileService(
        client: client,
        requestDeadline: const Duration(milliseconds: 10),
      );
      final owner = Object();
      const url = 'https://provider.test/slow.jpg';
      ArtworkRepository.demand(url, owner, ArtworkPriority.visible);
      await expectLater(
        service.get(url),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(client.aborted, isTrue);
      ArtworkRepository.release(url, owner);
    },
  );
  testWidgets(
    'Lite never constructs a downloader and offscreen cast remains unloaded',
    (tester) async {
      await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
      await tester.pumpWidget(
        const MaterialApp(
          home: SizedBox(
            width: 100,
            height: 100,
            child: SharedArtworkImage(
              imageUrl: 'https://provider.test/photo.jpg',
              kind: ArtworkKind.cast,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: const [
              SizedBox(height: 1200),
              SizedBox(
                width: 100,
                height: 100,
                child: SharedArtworkImage(
                  imageUrl: 'https://provider.test/photo.jpg',
                  kind: ArtworkKind.cast,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsNothing);
      scroll.jumpTo(1100);
      await tester.pumpAndSettle();
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
