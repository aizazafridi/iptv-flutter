import 'dart:convert';
import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:iptv_flutter/data/subtitle_service.dart';

void main() {
  test(
    'subtitle API maps results, identifies episodes and downloads the chosen file',
    () async {
      final server = await io.HttpServer.bind(
        io.InternetAddress.loopbackIPv4,
        0,
      );
      final requests = <io.HttpRequest>[];
      server.listen((request) async {
        requests.add(request);
        expect(request.headers.value('Api-Key'), 'fixture-key');
        request.response.headers.contentType = io.ContentType.json;
        if (request.uri.path.endsWith('/subtitles')) {
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'attributes': {
                    'release': 'Other',
                    'files': [
                      {'file_id': 9},
                    ],
                  },
                },
                {
                  'attributes': {
                    'release': 'Wrong episode',
                    'feature_details': {
                      'parent_title': 'Example',
                      'season_number': 2,
                      'episode_number': 4,
                    },
                    'files': [
                      {'file_id': 99},
                    ],
                  },
                },
                {
                  'attributes': {
                    'release': 'Pilot',
                    'feature_details': {
                      'parent_title': 'Example',
                      'season_number': 2,
                      'episode_number': 3,
                    },
                    'language': 'en',
                    'files': [
                      {'file_id': 42},
                    ],
                  },
                },
              ],
            }),
          );
        } else {
          expect(request.headers.contentLength, greaterThan(0));
          expect(request.headers.chunkedTransferEncoding, isFalse);
          expect(request.headers.value('Accept'), 'application/json');
          request.response.statusCode = 201;
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          expect(body['file_id'], 42);
          request.response.write(
            jsonEncode({'link': 'https://example.com/subtitle.srt'}),
          );
        }
        await request.response.close();
      });
      try {
        final service = SubtitleService(
          'fixture-key',
          endpoint: Uri.parse('http://127.0.0.1:${server.port}/api/v1/'),
        );
        final results = await service.search('Example · S2 E3 · Pilot', 'en');
        expect(results.first.fileId, 42);
        expect(results.map((result) => result.fileId), [42, 9]);
        expect(requests.first.uri.queryParameters, {
          'episode_number': '3',
          'languages': 'en',
          'query': 'Example',
          'season_number': '2',
        });
        expect((await service.download(results.first)).path, '/subtitle.srt');
      } finally {
        await server.close(force: true);
      }
    },
  );
}
