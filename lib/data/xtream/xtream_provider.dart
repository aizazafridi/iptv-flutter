import 'dart:convert';
import '../../domain/iptv_provider.dart';
import '../../domain/models.dart';
import 'xtream_client.dart';

/// All Xtream response mapping lives here. No raw dictionaries reach a screen.
class XtreamProvider implements IptvProvider, EpgProvider, CatchUpProvider {
  final XtreamClient client;
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

  DateTime? _timestamp(dynamic value) {
    final seconds = int.tryParse(_text(value));
    if (seconds == null || seconds <= 0 || seconds >= 8640000000000) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

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
    final idField = type == ContentType.series ? 'series_id' : 'stream_id';
    // Providers sometimes include blank separator entries. Keep valid channels
    // available even when one catalogue entry has no usable identifier.
    return rows
        .whereType<Map<String, dynamic>>()
        .where((row) => _text(row[idField]).trim().isNotEmpty)
        .map((row) {
          return ContentItem(
            id: _required(
              row,
              type == ContentType.series ? 'series_id' : 'stream_id',
            ),
            name: _text(row['name']).trim().isEmpty
                ? '${type.label} ${row[idField]}'
                : _text(row['name']),
            type: type,
            artwork: _image(row['stream_icon'] ?? row['cover']),
            extension: row['container_extension']?.toString(),
            categoryId: row['category_id']?.toString() ?? categoryId,
            addedAt:
                _timestamp(row['added']) ??
                (type == ContentType.series
                    ? _timestamp(row['last_modified'])
                    : null),
          );
        })
        .toList();
  }

  MediaDetails _details(ContentItem item, Map<String, dynamic> info) {
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
          _image(info['movie_image']) ??
          _image(info['cover_big']) ??
          _image(info['cover']) ??
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
      addedAt: movie.addedAt,
      categoryId: movie.categoryId,
      extension:
          movieData['container_extension']?.toString() ?? movie.extension,
    );
    return _details(
      item,
      data['info'] is Map<String, dynamic> ? _map(data['info']) : {},
    );
  }

  Uri? _episodeArtwork(Map<String, dynamic> row) {
    final info = row['info'] is Map ? row['info'] as Map : const {};
    // Empty/invalid fields must not hide another valid provider image.
    for (final value in [
      info['movie_image'],
      info['cover_big'],
      info['cover'],
      info['thumbnail'],
      row['movie_image'],
      row['cover_big'],
      row['cover'],
      row['thumbnail'],
    ]) {
      final image = _image(value);
      if (image != null) return image;
    }
    return null;
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
            artwork: _episodeArtwork(row) ?? _details(series, info).artwork,
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
            (item.type == ContentType.live ? 'ts' : 'mp4'),
      ),
      title: episode == null
          ? item.name
          : '${item.name} · S${episode.season} E${episode.number} · ${episode.title}',
      isLive: item.type == ContentType.live,
      headers: const {'User-Agent': 'VLC/3.0.21 LibVLC/3.0.21'},
    );
  }

  // Unix timestamps avoid interpreting the provider's timezone as device time.
  @override
  Future<List<EpgProgramme>> getEpg(ContentItem channel) async {
    if (channel.type != ContentType.live) return [];
    List<EpgProgramme> short = [];
    try {
      short = _epgRows(
        await client.request(
          action: 'get_short_epg',
          params: {'stream_id': channel.id, 'limit': '100'},
        ),
      );
    } on ProviderException {
      /* Try the full guide when short EPG is unsupported. */
    }
    if (short.any((p) => p.isCurrent(DateTime.now()))) return short;
    try {
      final full = _epgRows(
        await client.request(
          action: 'get_simple_data_table',
          params: {'stream_id': channel.id},
        ),
      );
      // Short EPG can omit the current show. Merge full EPG without duplicates.
      final merged = <String, EpgProgramme>{};
      for (final p in [...full, ...short]) {
        merged['${p.start.millisecondsSinceEpoch}:${p.end.millisecondsSinceEpoch}:${p.title}'] =
            p;
      }
      return merged.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    } on ProviderException {
      if (short.isEmpty) rethrow;
      return short;
    }
  }

  @override
  Future<bool> supportsCatchUp(ContentItem channel) async {
    if (channel.type != ContentType.live) return false;
    final rows = _list(
      await client.request(
        action: 'get_live_streams',
        params: {'category_id': ?channel.categoryId},
      ),
    );
    return rows.whereType<Map<String, dynamic>>().any(
      (row) =>
          _text(row['stream_id']) == channel.id &&
          _text(row['tv_archive']) == '1' &&
          (int.tryParse(_text(row['tv_archive_duration'])) ?? 0) > 0,
    );
  }

  @override
  Future<List<EpgProgramme>> getCatchUp(ContentItem channel) async {
    if (channel.type != ContentType.live) return [];
    // Fetch current capabilities even for channels restored from My List.
    final channels = _list(
      await client.request(
        action: 'get_live_streams',
        params: {'category_id': ?channel.categoryId},
      ),
    );
    final matching = channels.whereType<Map<String, dynamic>>().where(
      (row) => _text(row['stream_id']) == channel.id,
    );
    if (matching.isEmpty) return [];
    final row = matching.first;
    final days = int.tryParse(_text(row['tv_archive_duration'])) ?? 0;
    if (_text(row['tv_archive']) != '1' || days <= 0) return [];
    final response = _map(
      await client.request(
        action: 'get_simple_data_table',
        params: {'stream_id': channel.id},
      ),
    );
    final rows = _list(response['epg_listings'] ?? [])
        .whereType<Map<String, dynamic>>()
        .where((row) => _text(row['has_archive']) == '1')
        .toList();
    final now = DateTime.now();
    final earliest = now.subtract(Duration(days: days));
    return _epgRows({'epg_listings': rows})
        .where(
          (p) =>
              p.archiveStart != null &&
              !p.start.isBefore(earliest) &&
              !p.end.isAfter(now),
        )
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start));
  }

  @override
  Future<PlaybackSource> resolveCatchUp(
    ContentItem channel,
    EpgProgramme programme,
  ) async {
    final now = DateTime.now();
    if (channel.type != ContentType.live ||
        programme.archiveStart == null ||
        programme.end.isAfter(now) ||
        !programme.end.isAfter(programme.start)) {
      throw const ProviderException(
        'This programme is not available for catch-up.',
      );
    }
    return PlaybackSource(
      uri: client.catchUp(
        channel.id,
        programme.archiveStart!,
        (programme.end.difference(programme.start).inSeconds / 60).ceil(),
      ),
      title: '${channel.name} ? ${programme.title}',
      headers: const {'User-Agent': 'VLC/3.0.21 LibVLC/3.0.21'},
    );
  }

  String? _archiveStart(dynamic value) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})[ T](\d{2}):(\d{2}):\d{2}$',
    ).firstMatch(_text(value));
    return match == null ? null : '${match[1]}:${match[2]}-${match[3]}';
  }

  List<EpgProgramme> _epgRows(dynamic response) {
    final raw = _map(response)['epg_listings'];
    if (raw == null || raw is List && raw.isEmpty) return [];
    final result = <EpgProgramme>[];
    for (final value in _list(raw)) {
      if (value is! Map<String, dynamic>) continue;
      final start = _timestamp(value['start_timestamp']);
      final end = _timestamp(value['stop_timestamp'] ?? value['end_timestamp']);
      // Do not guess a timezone for ambiguous server date strings.
      if (start == null || end == null || !end.isAfter(start)) continue;
      result.add(
        EpgProgramme(
          archiveStart: _archiveStart(value['start']),
          title: _epgText(value['title']),
          description: _epgText(value['description']),
          start: start,
          end: end,
        ),
      );
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  String _epgText(dynamic value) {
    final text = _text(value);
    try {
      final decoded = utf8.decode(base64.decode(base64.normalize(text)));
      if (decoded.runes.any((r) => r < 32 && r != 10 && r != 13 && r != 9)) {
        return text;
      }
      return decoded;
    } catch (_) {
      return text;
    }
  }

  @override
  void dispose() => client.dispose();
}
