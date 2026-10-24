import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import '../../domain/iptv_provider.dart';
import '../../domain/models.dart';
import '../server_http_error.dart';

class M3uEntry {
  final ContentItem item;
  final Uri stream;
  final String group;
  final Map<String, String> headers;
  const M3uEntry(this.item, this.stream, this.group, this.headers);
}

String _id(String value) {
  // Stable IDs keep credentials and signed stream URLs out of saved history.
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return hash.toRadixString(16);
}

/// Parses extended IPTV M3U playlists; HLS media manifests are not catalogues.
List<M3uEntry> parseM3u(String text, Uri base) {
  text = text.replaceFirst('\uFEFF', '').trim();
  if (!text.startsWith('#EXTM3U') ||
      text.contains('#EXT-X-TARGETDURATION:') ||
      text.contains('#EXT-X-STREAM-INF:')) {
    throw const ProviderException(
      'Enter an IPTV M3U playlist URL, not a video stream or web page.',
    );
  }
  final result = <M3uEntry>[];
  final seen = <String>{};
  var name = '', group = 'Ungrouped';
  Uri? artwork;
  var headers = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF:')) {
      final attributes = <String, String>{};
      for (final match in RegExp(
        r'''([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
      ).allMatches(line)) {
        attributes[match[1]!.toLowerCase()] = match[2] ?? match[3]!;
      }
      // Commas inside quoted attributes belong to metadata, not the title.
      String? quote;
      var comma = -1;
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (quote != null) {
          if (c == quote) quote = null;
        } else if (c == '"' || c == "'") {
          quote = c;
        } else if (c == ',') {
          comma = i;
          break;
        }
      }
      name = comma >= 0 ? line.substring(comma + 1).trim() : '';
      if (name.isEmpty) name = attributes['tvg-name'] ?? '';
      group = attributes['group-title']?.trim() ?? 'Ungrouped';
      if (group.isEmpty) group = 'Ungrouped';
      final logo = attributes['tvg-logo'];
      artwork = logo == null || logo.isEmpty ? null : base.resolve(logo);
      if (artwork != null && !['http', 'https'].contains(artwork.scheme)) {
        artwork = null;
      }
      headers = {};
    } else if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
      if (group.isEmpty) group = 'Ungrouped';
    } else if (line.startsWith('#EXTVLCOPT:')) {
      final option = line.substring(11);
      final separator = option.indexOf('=');
      if (separator > 0) {
        final key = switch (option.substring(0, separator)) {
          'http-user-agent' => 'User-Agent',
          'http-referrer' => 'Referer',
          _ => null,
        };
        final value = option.substring(separator + 1);
        if (key != null && !value.contains('\r') && !value.contains('\n')) {
          headers[key] = value;
        }
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      final stream = base.resolve(line);
      if (['http', 'https', 'rtsp', 'rtmp', 'udp'].contains(stream.scheme) &&
          seen.add(stream.toString())) {
        final id = _id(stream.toString());
        result.add(
          M3uEntry(
            ContentItem(
              id: id,
              name: name.isEmpty ? 'Channel ${result.length + 1}' : name,
              type: ContentType.live,
              categoryId: _id(group),
              artwork: artwork,
            ),
            stream,
            group,
            Map.of(headers),
          ),
        );
      }
      name = '';
      group = 'Ungrouped';
      artwork = null;
      headers = {};
    }
  }
  if (result.isEmpty) {
    throw const ProviderException(
      'The playlist contains no playable channels.',
    );
  }
  return result;
}

/// M3U is an independent provider: no Xtream credentials or endpoints are used.
class M3uProvider implements IptvProvider {
  final ProviderConfig config;
  final HttpClient _http;
  late final Uri uri;
  Future<List<M3uEntry>>? _loading;
  bool disposed = false;
  M3uProvider(this.config, {HttpClient? http}) : _http = http ?? HttpClient() {
    final parsed = Uri.tryParse(config.server.trim());
    if (parsed == null ||
        !['http', 'https'].contains(parsed.scheme) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw const ProviderException(
        'Enter a valid HTTP or HTTPS M3U playlist URL.',
      );
    }
    uri = parsed;
    _http.connectionTimeout = const Duration(seconds: 20);
  }
  @override
  String get displayName => 'M3U Playlist';
  @override
  Set<ContentType> get supportedTypes => {ContentType.live};

  Future<List<M3uEntry>> entries() async {
    if (disposed) {
      throw const ProviderException('This playlist connection is closed.');
    }
    try {
      return await (_loading ??= download().timeout(
        const Duration(seconds: 40),
      ));
    } on ProviderException {
      _loading = null;
      rethrow;
    } catch (_) {
      _loading = null;
      throw const ProviderException(
        'Could not load the playlist. Check its URL and your connection.',
      );
    }
  }

  Future<List<M3uEntry>> download() async {
    final request = await _http.getUrl(uri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/x-mpegURL, audio/x-mpegurl, text/plain, */*',
    );
    request.headers.set(HttpHeaders.userAgentHeader, 'Streamora');
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw serverHttpError(response.statusCode, service: 'M3U playlist');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 50 * 1000 * 1000) {
        throw const ProviderException('The playlist exceeds the 50 MB limit.');
      }
      bytes.add(chunk);
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    final base = response.redirects.isEmpty
        ? uri
        : response.redirects.fold<Uri>(
            uri,
            (base, redirect) => base.resolveUri(redirect.location),
          );
    return Isolate.run(() => parseM3u(text, base));
  }

  @override
  Future<Account> connect() async {
    await entries();
    return const Account('M3U Playlist', 'Active', null);
  }

  @override
  Future<List<Category>> getCategories(ContentType type) async {
    if (type != ContentType.live) return [];
    final categories = <String, Category>{};
    for (final entry in await entries()) {
      categories.putIfAbsent(
        entry.item.categoryId!,
        () => Category(entry.item.categoryId!, entry.group, type),
      );
    }
    return categories.values.toList();
  }

  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async =>
      type == ContentType.live
      ? (await entries()).map((e) => e.item).toList()
      : [];
  @override
  Future<List<ContentItem>> getItems(Category category) async =>
      (await getAllItems(
        category.type,
      )).where((item) => item.categoryId == category.id).toList();
  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    final entry = (await entries())
        .where((e) => e.item.id == item.id)
        .firstOrNull;
    if (entry == null) {
      throw const ProviderException(
        'This channel is no longer in the playlist.',
      );
    }
    return PlaybackSource(
      uri: entry.stream,
      title: entry.item.name,
      isLive: true,
      headers: entry.headers,
    );
  }

  @override
  Future<MediaDetails> getMovieDetails(ContentItem movie) async =>
      throw const ProviderException(
        'This playlist supports Live TV channels only.',
      );
  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem series) async =>
      throw const ProviderException(
        'This playlist supports Live TV channels only.',
      );
  @override
  void dispose() {
    disposed = true;
    _http.close(force: true);
  }
}
