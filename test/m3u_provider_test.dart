import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/m3u/m3u_provider.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test(
    'extended M3U parses quoted groups, relative artwork and stream headers',
    () {
      final rows = parseM3u('''\uFEFF#EXTM3U
#EXTINF:-1 tvg-name="Fallback" tvg-logo="images/logo.png" group-title="News, International",World News
#EXTVLCOPT:http-user-agent=ExamplePlayer
#EXTVLCOPT:http-referrer=https://example.com/
streams/news.m3u8?token=secret
#EXTINF:-1,Second channel
#EXTGRP:Sports
https://example.com/sport.ts
#EXTINF:-1,Duplicate
streams/news.m3u8?token=secret
''', Uri.parse('https://example.com/playlist/list.m3u'));
      expect(rows, hasLength(2));
      expect(rows.first.group, 'News, International');
      expect(rows.first.item.name, 'World News');
      expect(
        rows.first.item.artwork.toString(),
        'https://example.com/playlist/images/logo.png',
      );
      expect(
        rows.first.stream.toString(),
        'https://example.com/playlist/streams/news.m3u8?token=secret',
      );
      expect(rows.first.headers['User-Agent'], 'ExamplePlayer');
      expect(rows.first.headers['Referer'], 'https://example.com/');
      expect(rows.last.headers, isEmpty);
      expect(rows.last.group, 'Sports');
      expect(rows.first.item.id, isNot(contains('secret')));
      final reordered = parseM3u(
        '#EXTM3U\n#EXTINF:-1,Renamed\nstreams/news.m3u8?token=secret',
        Uri.parse('https://example.com/playlist/list.m3u'),
      );
      expect(reordered.single.item.id, rows.first.item.id);
    },
  );
  test('rejects web pages, empty playlists and HLS media manifests', () {
    for (final text in [
      '<html>Forbidden</html>',
      '#EXTM3U',
      '#EXTM3U\n#EXT-X-TARGETDURATION:6\npart.ts',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100\nvideo.m3u8',
    ]) {
      expect(
        () => parseM3u(text, Uri.parse('https://example.com/')),
        throwsA(isA<ProviderException>()),
      );
    }
  });
  test(
    'provider downloads once, groups channels and resolves playback without Xtream',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        expect(request.uri.path, '/playlist.m3u');
        request.response.write(
          '#EXTM3U\n#EXTINF:-1 group-title="News",Example channel\nhttps://example.com/live.m3u8',
        );
        await request.response.close();
      });
      final provider = M3uProvider(
        ProviderConfig(
          providerId: 'm3u',
          server: 'http://127.0.0.1:${server.port}/playlist.m3u',
          username: '',
          password: '',
        ),
      );
      try {
        expect((await provider.connect()).status, 'Active');
        expect(provider.supportedTypes, {ContentType.live});
        final categories = await provider.getCategories(ContentType.live);
        expect(categories.single.name, 'News');
        final channels = await provider.getItems(categories.single);
        final source = await provider.resolvePlayback(channels.single);
        expect(source.uri.toString(), 'https://example.com/live.m3u8');
        expect(source.isLive, isTrue);
        expect(await provider.getAllItems(ContentType.movies), isEmpty);
        expect(requests, 1);
      } finally {
        provider.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
  test(
    'failed download is retryable and error omits signed playlist URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      final subscription = server.listen((request) async {
        if (++requests == 1) {
          request.response.statusCode = 403;
        } else {
          request.response.write(
            '#EXTM3U\n#EXTINF:-1,Channel\nhttps://example.com/live.ts',
          );
        }
        await request.response.close();
      });
      final provider = M3uProvider(
        ProviderConfig(
          providerId: 'm3u',
          server: 'http://127.0.0.1:${server.port}/playlist.m3u?token=private',
          username: '',
          password: '',
        ),
      );
      try {
        await expectLater(
          provider.connect(),
          throwsA(
            isA<ProviderException>().having(
              (e) => e.message,
              'safe error',
              allOf(
                contains('server refused the connection'),
                isNot(contains('private')),
              ),
            ),
          ),
        );
        expect((await provider.connect()).status, 'Active');
      } finally {
        provider.dispose();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
  );
}
