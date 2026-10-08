import '../../domain/iptv_provider.dart';
import '../../domain/models.dart';
import 'xtream_client.dart';

/// All Xtream response mapping lives here. No raw dictionaries reach a screen.
class XtreamProvider implements IptvProvider {
  final XtreamClient client;
  final Map<String, String> _knownCast = {};
  @override
  final String displayName;
  XtreamProvider(this.client, {this.displayName = 'Xtream Codes'});
  @override
  Set<ContentType> get supportedTypes => ContentType.values.toSet();

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const ProviderException(
        'The server returned an unexpected response.',
      );
    }
    return value;
  }

  List<dynamic> _list(dynamic value) {
    if (value is! List) {
      throw const ProviderException(
        'The server returned an invalid content list.',
      );
    }
    return value;
  }

  String _text(dynamic value) => value?.toString() ?? '';
  String _required(Map<String, dynamic> data, String field) {
    final value = _text(data[field]);
    if (value.isEmpty) {
      throw const ProviderException(
        'The server returned incomplete content information.',
      );
    }
    return value;
  }

  Uri? _image(dynamic value) {
    final uri = Uri.tryParse(_text(value));
    return uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty
        ? uri
        : null;
  }

  int _number(dynamic value) => int.tryParse(_text(value)) ?? 0;

  @override
  Future<Account> connect() async {
    final user = _map(_map(await client.request())['user_info']);
    if (_text(user['auth']) != '1') {
      throw const ProviderException(
        'Authentication failed. Check your account credentials.',
      );
    }
    final timestamp = int.tryParse(_text(user['exp_date']));
    DateTime? expiry;
    if (timestamp != null && timestamp > 0 && timestamp < 8640000000000) {
      expiry = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
    }
    return Account(_text(user['username']), _text(user['status']), expiry);
  }

  @override
  Future<List<Category>> getCategories(ContentType type) async {
    final action = switch (type) {
      ContentType.live => 'get_live_categories',
      ContentType.movies => 'get_vod_categories',
      ContentType.series => 'get_series_categories',
    };
    return _list(await client.request(action: action)).map((raw) {
      final row = _map(raw);
      return Category(
        _required(row, 'category_id'),
        _required(row, 'category_name'),
        type,
      );
    }).toList();
  }

  @override
  Future<List<ContentItem>> getItems(Category category) =>
      _getItems(category.type, categoryId: category.id);

  @override
  Future<List<ContentItem>> getAllItems(ContentType type) => _getItems(type);

  Future<List<ContentItem>> _getItems(
    ContentType type, {
    String? categoryId,
  }) async {
    final action = switch (type) {
      ContentType.live => 'get_live_streams',
      ContentType.movies => 'get_vod_streams',
      ContentType.series => 'get_series',
    };
    final rows = _list(
      await client.request(
        action: action,
        params: {'category_id': ?categoryId},
      ),
    );
    return rows.map((raw) {
      final row = _map(raw);
      return ContentItem(
        id: _required(
          row,
          type == ContentType.series ? 'series_id' : 'stream_id',
        ),
        name: _required(row, 'name'),
        type: type,
        artwork: _image(row['stream_icon'] ?? row['cover']),
        extension: row['container_extension']?.toString(),
        cast: row['cast'] == null
            ? _knownCast['${type.name}:${row[type == ContentType.series ? 'series_id' : 'stream_id']}']
            : _text(row['cast']),
      );
    }).toList();
  }

  MediaDetails _details(ContentItem item, Map<String, dynamic> info) {
    final cast = _text(info['cast']);
    _knownCast['${item.type.name}:${item.id}'] = cast;
    return MediaDetails(
      item: item,
      synopsis: _text(info['plot'] ?? info['description']),
      genre: _text(info['genre']),
      cast: _text(info['cast']),
      director: _text(info['director']),
      rating: _text(info['rating']),
      releaseDate: _text(info['releasedate'] ?? info['releaseDate']),
      duration: _text(info['duration']),
      artwork:
          _image(info['movie_image'] ?? info['cover_big'] ?? info['cover']) ??
          item.artwork,
    );
  }

  @override
  Future<MediaDetails> getMovieDetails(ContentItem movie) async {
    final data = _map(
      await client.request(
        action: 'get_vod_info',
        params: {'vod_id': movie.id},
      ),
    );
    final movieData = _map(data['movie_data']);
    final item = ContentItem(
      id: movie.id,
      name: movie.name,
      type: movie.type,
      artwork: movie.artwork,
      extension:
          movieData['container_extension']?.toString() ?? movie.extension,
    );
    return _details(
      item,
      data['info'] is Map<String, dynamic> ? _map(data['info']) : {},
    );
  }

  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem series) async {
    final data = _map(
      await client.request(
        action: 'get_series_info',
        params: {'series_id': series.id},
      ),
    );
    final info = _map(data['info']);
    final raw = data['episodes'];
    final groups = raw == null || (raw is List && raw.isEmpty)
        ? <String, dynamic>{}
        : _map(raw);
    final episodes = <Episode>[];
    for (final group in groups.entries) {
      for (final rawEpisode in _list(group.value)) {
        final row = _map(rawEpisode);
        episodes.add(
          Episode(
            id: _required(row, 'id'),
            title: _text(row['title']),
            season: _number(row['season'] ?? group.key),
            number: _number(row['episode_num']),
            extension: _text(row['container_extension']).isEmpty
                ? 'mp4'
                : _text(row['container_extension']),
          ),
        );
      }
    }
    episodes.sort(
      (a, b) => a.season == b.season
          ? a.number.compareTo(b.number)
          : a.season.compareTo(b.season),
    );
    return SeriesDetails(_details(series, info), episodes);
  }

  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    if (item.type == ContentType.series && episode == null) {
      throw const ProviderException('Choose an episode to play.');
    }
    final kind = switch (item.type) {
      ContentType.live => 'live',
      ContentType.movies => 'movie',
      ContentType.series => 'series',
    };
    return PlaybackSource(
      uri: client.stream(
        kind,
        episode?.id ?? item.id,
        episode?.extension ??
            item.extension ??
            (item.type == ContentType.live ? 'm3u8' : 'mp4'),
      ),
      title: episode == null
          ? item.name
          : '${item.name} · S${episode.season} E${episode.number} · ${episode.title}',
      isLive: item.type == ContentType.live,
    );
  }

  @override
  void dispose() => client.dispose();
}
