import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class CompanionError implements Exception {
  final int status;
  final String message;
  const CompanionError(this.status, this.message);
}

/// Opt-in LAN server. No credentials or playback URLs cross this boundary.
class PhoneCompanionServer {
  final String page;
  final Future<Object> Function(String, Map<String, dynamic>) dispatch;
  final bool Function() isCurrentProfile;
  final void Function()? onChanged;
  final DateTime Function() clock;
  PhoneCompanionServer({
    required this.page,
    required this.dispatch,
    required this.isCurrentProfile,
    this.onChanged,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  HttpServer? _server;
  final _random = Random.secure();
  final _sessions = <String, DateTime>{};
  final _hosts = <String>{};
  final urls = <String>[];
  String code = '';
  DateTime _codeExpiry = DateTime(1970), _attemptWindow = DateTime(1970);
  int _attempts = 0, _active = 0;
  Future<void> _writes = Future.value();
  bool get running => _server != null;
  bool get codeExpired => code.isNotEmpty && clock().isAfter(_codeExpiry);
  int get pairedCount {
    _sessions.removeWhere((_, expiry) => expiry.isBefore(clock()));
    return _sessions.length;
  }

  void newCode() {
    code = (100000 + _random.nextInt(900000)).toString();
    _codeExpiry = clock().add(const Duration(minutes: 5));
    onChanged?.call();
  }

  Future<void> start({InternetAddress? address}) async {
    if (running) return;
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = interfaces
        .expand((i) => i.addresses)
        .where((a) => !a.isLoopback && _private(a))
        .toList();
    if (address == null && addresses.isEmpty) {
      throw const CompanionError(
        503,
        'Connect this device to your home Wi-Fi first.',
      );
    }
    final server = await HttpServer.bind(address ?? InternetAddress.anyIPv4, 0);
    _server = server;
    server.idleTimeout = const Duration(seconds: 15);
    final advertised = address == null ? addresses : [address];
    for (final a in advertised) {
      final host = '${a.address}:${server.port}';
      _hosts.add(host);
      urls.add('http://$host');
    }
    newCode();
    server.listen((r) => unawaited(_handle(r)));
  }

  static bool _private(InternetAddress a) {
    final b = a.rawAddress;
    return b.length == 4 &&
        (b[0] == 10 ||
            b[0] == 127 ||
            (b[0] == 192 && b[1] == 168) ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31));
  }

  Future<Map<String, dynamic>> _body(HttpRequest r) async {
    if (r.headers.contentType?.mimeType != 'application/json') {
      throw const CompanionError(415, 'Expected JSON.');
    }
    if (r.contentLength > 8192) {
      r.response.persistentConnection = false;
      throw const CompanionError(413, 'Request too large.');
    }
    final upload = Stopwatch()..start();
    var bytes = 0;
    final chunks = <int>[];
    await for (final chunk in r.timeout(const Duration(seconds: 5))) {
      if (upload.elapsed > const Duration(seconds: 5)) {
        throw const CompanionError(408, 'Request timed out.');
      }
      bytes += chunk.length;
      if (bytes <= 8192) chunks.addAll(chunk);
      // Drain finite oversized bodies without buffering them; the 5s timeout
      // bounds slow senders and keeps the next keep-alive request well formed.
    }
    if (bytes > 8192) throw const CompanionError(413, 'Request too large.');
    final body = jsonDecode(utf8.decode(chunks));
    if (body is! Map<String, dynamic>) throw const FormatException();
    return body;
  }

  Future<void> _handle(HttpRequest r) async {
    _active++;
    final response = r.response;
    response.headers
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Frame-Options', 'DENY')
      ..set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; connect-src 'self'; img-src 'none'",
      );
    try {
      if (!running || !isCurrentProfile()) {
        throw const CompanionError(401, 'Pair again with the current profile.');
      }
      if (_active > 8) throw const CompanionError(429, 'Too many requests.');
      final peer = r.connectionInfo?.remoteAddress;
      final host = r.headers.value('host');
      if (peer == null || !_private(peer) || !_hosts.contains(host)) {
        throw const CompanionError(403, 'Local network access only.');
      }
      final origin = r.headers.value('origin');
      if (origin != null && origin != 'http://$host') {
        throw const CompanionError(403, 'This origin is not allowed.');
      }
      if (r.method == 'GET' && r.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.write(page);
        return;
      }
      if (r.method != 'POST') throw const CompanionError(405, 'Use POST.');
      final body = await _body(r);
      Object result;
      if (r.uri.path == '/pair') {
        final now = clock();
        if (now.difference(_attemptWindow) > const Duration(minutes: 1)) {
          _attemptWindow = now;
          _attempts = 0;
        }
        if (++_attempts > 10) {
          throw const CompanionError(429, 'Wait a minute before trying again.');
        }
        if (code.isEmpty || now.isAfter(_codeExpiry) || body['code'] != code) {
          throw const CompanionError(401, 'Incorrect or expired pairing code.');
        }
        if (pairedCount >= 4) {
          throw const CompanionError(
            409,
            'Disconnect phones on the TV before pairing more.',
          );
        }
        final token = base64UrlEncode(
          List.generate(32, (_) => _random.nextInt(256)),
        );
        _sessions[token] = now.add(const Duration(hours: 12));
        code = ''; // Each TV code authorizes one phone only.
        onChanged?.call();
        result = {'token': token};
      } else {
        final auth = r.headers.value('authorization') ?? '';
        final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
        if (_sessions[token]?.isAfter(clock()) != true) {
          throw const CompanionError(401, 'Pair this phone with the TV first.');
        }
        if (r.uri.path == '/disconnect') {
          _sessions.remove(token);
          onChanged?.call();
          result = {'ok': true};
        } else if (const [
          '/search',
          '/list',
          '/groups',
          '/status',
        ].contains(r.uri.path)) {
          result = await dispatch(
            r.uri.path,
            body,
          ).timeout(const Duration(seconds: 30));
        } else if (const [
          '/favourite',
          '/membership',
          '/group',
          '/open',
        ].contains(r.uri.path)) {
          // Serialize mutations and recheck the session after queued work.
          final next = _writes.then((_) {
            if (!running ||
                !isCurrentProfile() ||
                !_sessions.containsKey(token)) {
              throw const CompanionError(401, 'Session ended.');
            }
            return dispatch(r.uri.path, body);
          });
          _writes = next.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          );
          result = await next;
        } else {
          throw const CompanionError(404, 'Unknown action.');
        }
      }
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(result));
    } on CompanionError catch (e) {
      response.statusCode = e.status;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': e.message}));
    } catch (_) {
      response.statusCode = 503;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'error': 'This action could not be completed. Please try again.',
        }),
      );
    } finally {
      _active--;
      try {
        await response.close();
      } catch (_) {
        /* Phone disconnected. */
      }
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.clear();
    _hosts.clear();
    urls.clear();
    code = '';
    await server?.close(force: true);
    onChanged?.call();
  }
}
