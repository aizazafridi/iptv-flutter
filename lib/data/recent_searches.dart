import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../application/universal_search.dart' show normalizeSearch;

class RecentSearches {
  final String scope;
  final FlutterSecureStorage storage;
  RecentSearches(this.scope, {this.storage = const FlutterSecureStorage()});
  Future<void> _writes = Future.value();
  String get key => 'recent_searches:$scope';
  Future<List<String>> load() async {
    try {
      final saved = await storage.read(key: key);
      if (saved == null) return [];
      return (jsonDecode(saved) as List)
          .whereType<String>()
          .where((s) => normalizeSearch(s).isNotEmpty)
          .take(8)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> add(String query) async {
    final cleaned = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizeSearch(cleaned).isEmpty) return load();
    var result = <String>[];
    final write = _writes.then((_) async {
      final rows = await load();
      result = [
        cleaned,
        ...rows.where((r) => normalizeSearch(r) != normalizeSearch(cleaned)),
      ].take(8).toList();
      await storage.write(key: key, value: jsonEncode(result));
    });
    _writes = write.catchError((_) {});
    await write;
    return result;
  }

  Future<void> clear() async {
    final write = _writes.then((_) => storage.delete(key: key));
    _writes = write.catchError((_) {});
    await write;
  }
}
