import '../domain/sports.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small public metadata cache, using the app's existing storage convention.
/// No playlist, stream URL, or account data is stored here.
class SportsApiCache extends ChangeNotifier {
  final FlutterSecureStorage storage;
  final DateTime Function() now;
  SportsApiCache({
    this.storage = const FlutterSecureStorage(),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final _memory = <String, Map<String, dynamic>>{};
  final _pending = <String, Future<Map<String, dynamic>>>{};
  final _retryAfter = <String, DateTime>{};
  String? updatedIdentity;
  String? error;
  DateTime? lastUpdated;
  bool closed = false;
  String key(String identity) =>
      'sports_cache_v1:${sha256.convert(utf8.encode(identity))}';
  Future<Map<String, dynamic>> get(
    String identity,
    Duration ttl,
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    final k = key(identity);
    var entry = _memory[k];
    if (entry == null) {
      try {
        final raw = await storage.read(key: k);
        if (raw != null) entry = jsonDecode(raw) as Map<String, dynamic>;
        if (entry != null) _memory[k] = entry;
      } catch (_) {
        /* Unavailable cache does not prevent a network request. */
      }
    }
    final saved = DateTime.tryParse(entry?['at']?.toString() ?? '');
    Future<Map<String, dynamic>> refresh() => _pending.putIfAbsent(k, () async {
      try {
        final data = await fetch();
        final stamp = now().toUtc();
        final next = <String, dynamic>{
          'at': stamp.toIso8601String(),
          'data': data,
        };
        _memory[k] = next;
        try {
          await storage.write(key: k, value: jsonEncode(next));
        } catch (_) {}
        _retryAfter.remove(k);
        updatedIdentity = identity;
        lastUpdated = stamp;
        error = null;
        if (!closed) notifyListeners();
        return data;
      } catch (e) {
        if (e is SportsRequestCancelled) rethrow;
        _retryAfter[k] = now().add(const Duration(minutes: 1));
        error = e.toString();
        if (!closed) notifyListeners();
        rethrow;
      } finally {
        _pending.remove(k);
      }
    });
    if (saved != null && entry?['data'] is Map) {
      lastUpdated = saved;
      if (now().toUtc().difference(saved) >= ttl &&
          !(_retryAfter[k]?.isAfter(now()) ?? false)) {
        // Stale-while-revalidate; subscriber can reload cached normalized data.
        unawaited(
          refresh().then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
      return Map<String, dynamic>.from(entry!['data'] as Map);
    }
    return refresh();
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}
