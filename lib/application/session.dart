import 'package:flutter/foundation.dart';
import 'dart:math';
import '../data/credential_store.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'provider_registry.dart';
import 'watch_history.dart';
import 'appearance.dart';

class Session extends ChangeNotifier {
  final ProviderRegistry registry;
  final CredentialStore store;
  AppAppearance? appearance;
  Session(this.registry, this.store, {this.appearance});
  IptvProvider? provider;
  Account? account;
  AccountProfile? activeProfile;
  List<AccountProfile> profiles = [];
  bool loading = true;
  String? error;
  ProviderConfig? lastConfig;
  bool _disposed = false;

  Future<void> initialize() async {
    try {
      final saved = await store.loadProfiles();
      if (_disposed) return;
      if (saved != null) {
        profiles = saved;
      } else {
        final legacy = await store.load();
        if (_disposed) return;
        if (legacy != null) {
          final id = WatchHistory.scopeFor(legacy);
          final config = _profileConfig(legacy, id);
          profiles = [
            AccountProfile(
              id: id,
              name: legacy.username,
              avatar: 0,
              config: config,
            ),
          ];
          await store.saveProfiles(profiles);
          for (final key in [
            'app_background',
            'app_card_views',
            'opensubtitles_api_key',
            'subtitle_appearance',
          ]) {
            if (await store.storage.read(key: '$key:$id') == null) {
              final saved = await store.storage.read(key: key);
              if (saved != null) {
                await store.storage.write(key: '$key:$id', value: saved);
              }
            }
          }
        }
        if (legacy != null) await store.clear();
      }
    } catch (_) {
      error = 'Could not read saved accounts. Please retry.';
    }
    loading = false;
    _notify();
  }

  ProviderConfig _profileConfig(ProviderConfig config, String id) =>
      ProviderConfig(
        providerId: config.providerId,
        server: config.server,
        username: config.username,
        password: config.password,
        profileId: id,
      );

  Future<void> selectProfile(AccountProfile profile) =>
      connect(profile.config, remember: false);
  Future<void> connect(
    ProviderConfig config, {
    bool remember = true,
    String? name,
    int avatar = 0,
  }) async {
    if (loading && provider != null) return;
    final existing = profiles
        .where((profile) => profile.id == config.profileId)
        .firstOrNull;
    if (existing == null && profiles.length >= 5) {
      error =
          'You can save up to five accounts. Remove an account to add another.';
      loading = false;
      _notify();
      return;
    }
    loading = true;
    error = null;
    _notify();
    final id =
        existing?.id ??
        config.profileId ??
        'profile-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
    final configured = _profileConfig(config, id);
    lastConfig = configured;
    IptvProvider? candidate;
    try {
      candidate = registry.create(configured);
      final result = await candidate.connect();
      if (_disposed) {
        candidate.dispose();
        return;
      }
      final profile =
          existing ??
          AccountProfile(
            id: id,
            name: name?.trim().isNotEmpty == true
                ? name!.trim()
                : config.username,
            avatar: avatar.clamp(0, profileAvatarCount - 1),
            config: configured,
          );
      if (existing == null) {
        await store.saveProfiles([...profiles, profile]);
        profiles = [...profiles, profile];
      }
      if (_disposed) {
        candidate.dispose();
        return;
      }
      await appearance?.activate(id);
      if (_disposed) {
        candidate.dispose();
        return;
      }
      provider?.dispose();
      provider = candidate;
      account = result;
      activeProfile = profile;
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

  /// Save edits under the same profile ID, preserving all account preferences.
  /// Validate changed credentials before replacing the working connection.
  Future<bool> updateCurrentProfile(
    ProviderConfig config, {
    required String name,
    required int avatar,
  }) async {
    final original = activeProfile;
    if (original == null || loading) return false;
    if (name.trim().isEmpty) {
      error = 'Enter an account name.';
      _notify();
      return false;
    }
    loading = true;
    error = null;
    _notify();
    IptvProvider? candidate;
    try {
      final configured = _profileConfig(config, original.id);
      final old = original.config;
      final changed =
          old.providerId != configured.providerId ||
          old.server != configured.server ||
          old.username != configured.username ||
          old.password != configured.password;
      Account? result;
      if (changed) {
        candidate = registry.create(configured);
        result = await candidate.connect();
      }
      if (_disposed) {
        candidate?.dispose();
        return false;
      }
      final updated = AccountProfile(
        id: original.id,
        name: name.trim(),
        avatar: avatar.clamp(0, profileAvatarCount - 1),
        config: configured,
      );
      final saved = profiles
          .map((p) => p.id == original.id ? updated : p)
          .toList();
      await store.saveProfiles(saved);
      if (_disposed) {
        candidate?.dispose();
        return false;
      }
      profiles = saved;
      activeProfile = updated;
      lastConfig = configured;
      if (candidate != null) {
        provider?.dispose();
        provider = candidate;
        account = result;
      }
      return true;
    } on ProviderException catch (exception) {
      candidate?.dispose();
      error = exception.message;
      return false;
    } catch (_) {
      candidate?.dispose();
      error = 'Could not save account changes. Please retry.';
      return false;
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> removeProfile(AccountProfile profile) async {
    final remaining = profiles
        .where((entry) => entry.id != profile.id)
        .toList();
    try {
      await store.saveProfiles(remaining);
      profiles = remaining;
      error = null;
      if (activeProfile?.id == profile.id) await signOut();
    } catch (_) {
      error = 'Could not remove this account. Please retry.';
    }
    _notify();
  }

  Future<void> signOut() async {
    provider?.dispose();
    provider = null;
    account = null;
    activeProfile = null;
    lastConfig = null;
    error = null;
    await appearance?.activate(null);
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
