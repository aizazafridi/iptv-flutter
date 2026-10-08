import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';

class CredentialStore {
  static const _key = 'iptv_account';
  final FlutterSecureStorage storage;
  const CredentialStore({this.storage = const FlutterSecureStorage()});
  Future<ProviderConfig?> load() async {
    final saved = await storage.read(key: _key);
    if (saved != null) {
      try {
        return ProviderConfig.fromJson(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } catch (_) {
        await clear();
      }
    }
    // Local development config is never used by release builds.
    if (!kReleaseMode) {
      const server = String.fromEnvironment('IPTV_SERVER');
      if (server.isNotEmpty) {
        return const ProviderConfig(
          providerId: String.fromEnvironment(
            'IPTV_PROVIDER',
            defaultValue: 'starshare',
          ),
          server: server,
          username: String.fromEnvironment('IPTV_USERNAME'),
          password: String.fromEnvironment('IPTV_PASSWORD'),
        );
      }
    }
    return null;
  }

  Future<void> save(ProviderConfig config) =>
      storage.write(key: _key, value: jsonEncode(config.toJson()));
  Future<void> clear() => storage.delete(key: _key);
}
