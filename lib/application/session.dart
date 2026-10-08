import 'package:flutter/foundation.dart';
import '../data/credential_store.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'provider_registry.dart';

class Session extends ChangeNotifier {
  final ProviderRegistry registry;
  final CredentialStore store;
  Session(this.registry, this.store);
  IptvProvider? provider;
  Account? account;
  bool loading = true;
  String? error;
  ProviderConfig? lastConfig;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      final config = await store.load();
      if (_disposed) return;
      if (config != null) {
        await connect(config, remember: false);
        return;
      }
    } catch (_) {
      error = 'Could not read saved account. Enter your details to reconnect.';
    }
    loading = false;
    _notify();
  }

  Future<void> connect(ProviderConfig config, {bool remember = true}) async {
    loading = true;
    error = null;
    lastConfig = config;
    _notify();
    IptvProvider? candidate;
    try {
      candidate = registry.create(config);
      final result = await candidate.connect();
      if (_disposed) {
        candidate.dispose();
        return;
      }
      if (remember) await store.save(config);
      if (_disposed) {
        candidate.dispose();
        return;
      }
      provider?.dispose();
      provider = candidate;
      account = result;
    } on ProviderException catch (exception) {
      candidate?.dispose();
      error = exception.message;
    } catch (_) {
      candidate?.dispose();
      error = 'Could not connect or securely save the account. Please retry.';
    }
    loading = false;
    _notify();
  }

  Future<void> signOut() async {
    try {
      await store.clear();
    } catch (_) {
      error = 'Could not clear saved credentials. Please retry.';
      _notify();
      return;
    }
    provider?.dispose();
    provider = null;
    account = null;
    lastConfig = null;
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    provider?.dispose();
    super.dispose();
  }
}
