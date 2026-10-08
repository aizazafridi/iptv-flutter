import 'dart:convert';
import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/xtream/xtream_client.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';

class FixtureClient extends XtreamClient {
  dynamic fixture;
  String? lastAction;
  Map<String, String> lastParams = {};
  FixtureClient()
    : super(
        const ProviderConfig(
          providerId: 'xtream',
          server: 'https://example.com/prefix',
          username: 'user name',
          password: 'p/a',
        ),
      );
  @override
  Future<dynamic> request({
    String? action,
    Map<String, String> params = const {},
  }) async {
    lastAction = action;
    lastParams = params;
    return fixture;
  }
}

void main() {
  late FixtureClient client;
  late XtreamProvider provider;
  setUp(() {
    client = FixtureClient();
    provider = XtreamProvider(client);
  });
  tearDown(() => provider.dispose());
  test('catalog search omits category filter for movies and series', () async {
    for (final type in [ContentType.movies, ContentType.series]) {
      client.fixture = [
        {'stream_id': 42, 'series_id': 42, 'name': 'Across categories'},
      ];
      final items = await provider.getAllItems(type);
      expect(items.single.name, 'Across categories');
      expect(client.lastParams, isEmpty);
      expect(
        client.lastAction,
        type == ContentType.movies ? 'get_vod_streams' : 'get_series',
      );
    }
  });
  test('auth rejection is distinct from successful transport', () async {
    client.fixture = {
      'user_info': {'auth': 0},
    };
    await expectLater(provider.connect(), throwsA(isA<ProviderException>()));
    client.fixture = {
      'user_info': {
        'auth': '1',
        'username': 'demo',
        'status': 'Active',
        'password': 'secret',
        'exp_date': '1735689600',
      },
    };
    final account = await provider.connect();
    expect(account.username, 'demo');
    expect(account.expiresAt, DateTime.utc(2025));
  });
  test('category actions and IDs map to provider-independent models', () async {
    for (final type in ContentType.values) {
      client.fixture = [
        {'category_id': 7, 'category_name': 'English'},
      ];
      final categories = await provider.getCategories(type);
      expect(categories.single.id, '7');
      expect(categories.single.type, type);
      expect(client.lastAction, switch (type) {
        ContentType.live => 'get_live_categories',
        ContentType.movies => 'get_vod_categories',
        ContentType.series => 'get_series_categories',
      });
      client.fixture = [
        {'stream_id': 42, 'series_id': 42, 'name': 'Example'},
      ];
      expect((await provider.getItems(categories.single)).single.id, '42');
      expect(client.lastParams, {'category_id': '7'});
    }
  });
  test(
    'series seasons and episode IDs drive playback, not series IDs',
    () async {
      const item = ContentItem(
        id: '99',
        name: 'Series',
        type: ContentType.series,
      );
      client.fixture = {
        'info': {'plot': 'Synopsis'},
        'episodes': {
          '2': [
            {
              'id': 52,
              'episode_num': 2,
              'title': 'Second',
              'container_extension': 'mkv',
            },
          ],
          '1': [
            {
              'id': 50,
              'episode_num': 1,
              'title': 'Pilot',
              'container_extension': 'mp4',
            },
          ],
        },
      };
      final result = await provider.getSeriesDetails(item);
      expect(result.episodes.first.id, '50');
      expect(client.lastParams, {'series_id': '99'});
      final source = await provider.resolvePlayback(
        item,
        episode: result.episodes.first,
      );
      expect(source.uri.pathSegments, [
        'prefix',
        'series',
        'user name',
        'p/a',
        '50.mp4',
      ]);
      await expectLater(
        provider.resolvePlayback(item),
        throwsA(isA<ProviderException>()),
      );
    },
  );
  test('movie details retain the provider container extension', () async {
    const item = ContentItem(id: '42', name: 'Movie', type: ContentType.movies);
    client.fixture = {
      'movie_data': {'container_extension': 'mkv'},
      'info': {'plot': 'Synopsis'},
    };
    final details = await provider.getMovieDetails(item);
    final source = await provider.resolvePlayback(details.item);
    expect(source.uri.pathSegments.last, '42.mkv');
    expect(client.lastParams, {'vod_id': '42'});
  });
  test('transport loads series JSON above the former 2 MB limit', () async {
    final server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = io.ContentType.json;
      request.response.write(
        jsonEncode([
          {'series_id': 42, 'name': 'Large', 'plot': 'x' * 2100000},
        ]),
      );
      request.response.close();
    });
    final transport = XtreamClient(
      ProviderConfig(
        providerId: 'xtream',
        server: 'http://127.0.0.1:${server.port}',
        username: 'demo',
        password: 'secret',
      ),
    );
    try {
      final rows = await transport.request(
        action: 'get_series',
        params: {'category_id': '7'},
      );
      expect(rows, isA<List>());
      await expectLater(transport.request(), throwsA(isA<ProviderException>()));
    } finally {
      transport.dispose();
      await server.close(force: true);
    }
  });
}
