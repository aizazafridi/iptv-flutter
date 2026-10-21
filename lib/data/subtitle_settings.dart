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
    // Use the configured default in desktop and release builds alike.
    const configured = String.fromEnvironment('OPENSUBTITLES_API_KEY');
    if (configured.isNotEmpty) return configured;
    final saved = await storage.read(key: key);
    if (saved != null && saved.isNotEmpty) return saved;
    return scope == null
        ? ''
        : await storage.read(key: 'opensubtitles_api_key') ?? '';
  }

  Future<void> save(String value) =>
      storage.write(key: key, value: value.trim());
}
