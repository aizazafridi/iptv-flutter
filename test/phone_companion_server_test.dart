import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:iptv_flutter/application/phone_companion_server.dart';

void main() {
  late PhoneCompanionServer server;
  late HttpClient client;
  late bool active;
  late DateTime now;
  var calls = 0;
  Future<({int status, dynamic body})> send(
    String path, {
    Map<String, dynamic>? body,
    String? token,
    String? origin,
    String? host,
  }) async {
    final r = await client.postUrl(Uri.parse('${server.urls.first}$path'));
    r.headers.contentType = ContentType.json;
    if (token != null) r.headers.set('authorization', 'Bearer $token');
    if (origin != null) r.headers.set('origin', origin);
    if (host != null) r.headers.set('host', host);
    r.write(jsonEncode(body ?? {}));
    final res = await r.close();
    return (
      status: res.statusCode,
      body: jsonDecode(await utf8.decoder.bind(res).join()),
    );
  }

  Future<String> pair() async {
    final response = await send('/pair', body: {'code': server.code});
    expect(response.status, 200);
    return response.body['token'] as String;
  }

  setUp(() async {
    active = true;
    now = DateTime.utc(2026, 11, 8);
    calls = 0;
    client = HttpClient();
    server = PhoneCompanionServer(
      page: '<h1>Pair</h1>',
      clock: () => now,
      isCurrentProfile: () => active,
      dispatch: (path, body) async {
        calls++;
        return {'ok': true};
      },
    );
    await server.start(address: InternetAddress.loopbackIPv4);
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });
  test('catalog and mutations require pairing, codes are single use', () async {
    expect((await send('/search')).status, 401);
    expect((await send('/open')).status, 401);
    final old = server.code;
    expect((await send('/pair', body: {'code': 'wrong'})).status, 401);
    final token = await pair();
    expect(server.pairedCount, 1);
    expect((await send('/pair', body: {'code': old})).status, 401);
    expect((await send('/search', token: token)).status, 200);
    expect(calls, 1);
  });
  test(
    'foreign origins and DNS rebinding hosts are rejected before pairing',
    () async {
      expect(
        (await send(
          '/pair',
          body: {'code': server.code},
          origin: 'https://evil.test',
        )).status,
        403,
      );
      expect(
        (await send(
          '/pair',
          body: {'code': server.code},
          host: 'evil.test',
        )).status,
        403,
      );
      expect(server.pairedCount, 0);
    },
  );
  test('disconnect and profile switch invalidate existing access', () async {
    final token = await pair();
    expect((await send('/disconnect', token: token)).status, 200);
    expect((await send('/search', token: token)).status, 401);
    server.newCode();
    final other = await pair();
    active = false;
    expect((await send('/open', token: other)).status, 401);
    expect(calls, 0);
  });
  test('oversized JSON and repeated wrong pairing codes are bounded', () async {
    expect((await send('/pair', body: {'code': 'x' * 9000})).status, 413);
    for (var i = 0; i < 10; i++) {
      expect((await send('/pair', body: {'code': 'bad'})).status, 401);
    }
    expect((await send('/pair', body: {'code': server.code})).status, 429);
  });
  test(
    'paired phones are limited, stopping revokes tokens on restart',
    () async {
      final first = await pair();
      for (var i = 0; i < 3; i++) {
        server.newCode();
        await pair();
      }
      server.newCode();
      expect((await send('/pair', body: {'code': server.code})).status, 409);
      await server.stop();
      expect(server.pairedCount, 0);
      await server.start(address: InternetAddress.loopbackIPv4);
      expect((await send('/search', token: first)).status, 401);
    },
  );
  test('mutations are serialized instead of racing My List writes', () async {
    final token = await pair();
    final results = await Future.wait(
      List.generate(4, (_) => send('/favourite', token: token)),
    );
    expect(results.every((r) => r.status == 200), isTrue);
    expect(calls, 4);
  });
  test(
    'pairing codes expire after five minutes and sessions after twelve hours',
    () async {
      final code = server.code;
      now = now.add(const Duration(minutes: 6));
      expect(server.codeExpired, true);
      expect((await send('/pair', body: {'code': code})).status, 401);
      server.newCode();
      final token = await pair();
      now = now.add(const Duration(hours: 13));
      expect((await send('/search', token: token)).status, 401);
      expect(server.pairedCount, 0);
    },
  );
}
