import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import '../../domain/models.dart';

/// Transport shared by Xtream-compatible providers. Replaceable in tests.
class XtreamClient {
  final ProviderConfig config;
  final HttpClient _http;
  late final Uri base;
  XtreamClient(this.config, {HttpClient? http}) : _http = http ?? HttpClient() {
    final uri = Uri.tryParse(config.server.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        config.username.isEmpty ||
        config.password.isEmpty) {
      throw const ProviderException(
        'Enter a valid server URL, username, and password.',
      );
    }
    var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/player_api.php')) {
      path = path.substring(0, path.length - '/player_api.php'.length);
    }
    base = uri.replace(path: path);
    _http.connectionTimeout = const Duration(seconds: 20);
  }

  Future<dynamic> request({
    String? action,
    Map<String, String> params = const {},
  }) async {
    final endpoint = base.replace(
      path: '${base.path}/player_api.php',
      queryParameters: {
        'username': config.username,
        'password': config.password,
        'action': ?action,
        ...params,
      },
    );
    final limit =
        {
          'get_live_streams',
          'get_vod_streams',
          'get_series',
          'get_series_info',
        }.contains(action)
        ? 50 * 1000 * 1000
        : 2 * 1000 * 1000;
    try {
      return await _download(
        endpoint,
        limit,
      ).timeout(const Duration(seconds: 40));
    } on ProviderException {
      rethrow;
    } catch (_) {
      throw const ProviderException(
        'Cannot reach the server. Check your connection and account settings.',
      );
    }
  }

  Future<dynamic> _download(Uri uri, int limit) async {
    final request = await _http.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'VLC/3.0.21 LibVLC/3.0.21',
    );
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw ProviderException('Server returned HTTP ${response.statusCode}.');
    }
    // Typed chunks avoid expanding a 50 MB response into hundreds of MB of ints.
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (buffer.length + chunk.length > limit) {
        throw ProviderException(
          'Response exceeds the ${limit ~/ 1000000} MB limit.',
        );
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    try {
      // Parsing large series lists off the UI isolate keeps navigation responsive.
      return await Isolate.run(
        () => jsonDecode(utf8.decode(bytes).replaceFirst('\uFEFF', '')),
      );
    } catch (_) {
      throw const ProviderException('Server returned invalid JSON.');
    }
  }

  Uri stream(String kind, String id, String extension) {
    if (!RegExp(r'^\d+$').hasMatch(id) ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)) {
      throw const ProviderException(
        'The server returned an invalid playback identifier.',
      );
    }
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((part) => part.isNotEmpty),
        kind,
        config.username,
        config.password,
        '$id.$extension',
      ],
    );
  }

  void dispose() => _http.close(force: true);
}
