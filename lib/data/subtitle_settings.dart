import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SubtitleSettings {
  final FlutterSecureStorage storage;
  final String? scope;
  String get key =>
      scope == null ? 'opensubtitles_api_key' : 'opensubtitles_api_key:$scope';
  const SubtitleSettings({
    this.storage = const FlutterSecureStorage(),
    this.scope,
  });
  Future<String> load() async {
    final saved = await storage.read(key: key);
    if (saved != null) return saved;
    // Seed local development settings once; user changes take precedence.
    const configured = String.fromEnvironment('OPENSUBTITLES_API_KEY');
    if (!kReleaseMode && configured.isNotEmpty) {
      await save(configured);
      return configured;
    }
    return '';
  }

  Future<void> save(String value) =>
      storage.write(key: key, value: value.trim());
}
