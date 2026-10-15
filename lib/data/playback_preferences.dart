import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PlaybackPreferences {
  final String scope;
  final FlutterSecureStorage storage;
  const PlaybackPreferences(
    this.scope, {
    this.storage = const FlutterSecureStorage(),
  });
  Future<Map<String, dynamic>> load() async {
    try {
      final saved = await storage.read(key: 'playback_settings:$scope');
      return saved == null ? {} : jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, dynamic> values) =>
      storage.write(key: 'playback_settings:$scope', value: jsonEncode(values));
}
