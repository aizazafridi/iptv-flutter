import 'dart:convert';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import 'watch_history.dart';

class CategoryLocks extends ChangeNotifier {
  static final _instances = Expando<CategoryLocks>();
  static CategoryLocks forProvider(IptvProvider provider) =>
      _instances[provider] ??= CategoryLocks(
        WatchHistory.forProvider(provider).scope,
      );
  static void attach(IptvProvider provider, CategoryLocks locks) {
    _instances[provider] = locks;
  }

  final String scope;
  final FlutterSecureStorage storage;
  CategoryLocks(this.scope, {this.storage = const FlutterSecureStorage()});
  String _password = '';
  Set<String> _locked = {};
  Set<String> _titles = {}, _hidden = {}, _hiddenTitles = {};
  final Set<String> _unlockedTitles = {};
  String titleKey(ContentItem item) => '${item.type.name}:${item.id}';
  bool titleHidden(ContentItem item) => _hiddenTitles.contains(titleKey(item));
  bool get needsPinUpgrade =>
      hasPassword && !RegExp(r'^[0-9]{6}$').hasMatch(_password);
  bool titleConfigured(ContentItem item) => _titles.contains(titleKey(item));
  bool titleLocked(ContentItem item) =>
      titleConfigured(item) && !_unlockedTitles.contains(titleKey(item));
  bool hidden(Category category) => _hidden.contains(key(category));
  final Set<String> _unlocked = {};
  Future<void>? _loading;
  bool get hasPassword => _password.isNotEmpty;
  String key(Category category) => '${category.type.name}:${category.id}';
  bool configured(Category category) => _locked.contains(key(category));
  bool isLocked(Category category) =>
      configured(category) && !_unlocked.contains(key(category));
  bool hasLocks(ContentType type) =>
      _locked.any((key) => key.startsWith('${type.name}:'));
  bool hasHidden(ContentType type) =>
      _hidden.any((key) => key.startsWith('${type.name}:'));
  bool check(String password) => _password.isNotEmpty && password == _password;
  Future<void> load() => _loading ??= () async {
    final saved = await storage.read(key: 'category_locks:$scope');
    if (saved != null) {
      final value = jsonDecode(saved) as Map<String, dynamic>;
      _password = value['password'] as String? ?? '';
      _locked = (value['categories'] as List? ?? []).cast<String>().toSet();
      _titles = (value['titles'] as List? ?? []).cast<String>().toSet();
      _hidden = (value['hidden'] as List? ?? []).cast<String>().toSet();
      _hiddenTitles = (value['hiddenTitles'] as List? ?? [])
          .cast<String>()
          .toSet();
    }
  }();
  Future<void> _save(String password, Set<String> locked) => storage.write(
    key: 'category_locks:$scope',
    value: jsonEncode({
      'password': password,
      'categories': locked.toList(),
      'titles': _titles.toList(),
      'hidden': _hidden.toList(),
      'hiddenTitles': _hiddenTitles.toList(),
    }),
  );
  Future<void> setPassword(String password, {String current = ''}) async {
    await load();
    if (hasPassword && !check(current)) {
      throw const ProviderException('Current lock password is incorrect.');
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(password)) {
      throw const ProviderException(
        'Use exactly six digits (0?9) for the parental PIN.',
      );
    }
    await _save(password, _locked);
    _password = password;
    _unlocked.clear();
    _unlockedTitles.clear();
    notifyListeners();
  }

  Future<void> setLocked(
    Category category,
    bool locked, {
    String password = '',
  }) async {
    await load();
    if (!hasPassword) {
      throw const ProviderException(
        'Set a category lock password in Settings first.',
      );
    }
    if (!locked && !check(password)) {
      throw const ProviderException('Incorrect lock password.');
    }
    final updated = Set<String>.from(_locked);
    if (locked) {
      updated.add(key(category));
    } else {
      updated.remove(key(category));
    }
    await _save(_password, updated);
    _locked = updated;
    _unlocked.remove(key(category));
    notifyListeners();
  }

  // Settings reuse the profile's existing PIN instead of requesting another one.
  Future<void> configureCategory(Category category, bool value) async {
    await load();
    await setLocked(category, value, password: _password);
  }

  Future<void> configureTitle(ContentItem item, bool value) async {
    await load();
    await setTitleLocked(item, value, password: _password);
  }

  bool unlock(Category category, String password) {
    if (!check(password)) return false;
    _unlocked.add(key(category));
    notifyListeners();
    return true;
  }

  Future<void> setTitleLocked(
    ContentItem item,
    bool locked, {
    String password = '',
  }) async {
    await load();
    if (!hasPassword) {
      throw const ProviderException('Set a parental PIN first.');
    }
    if (!locked && !check(password)) {
      throw const ProviderException('Incorrect PIN.');
    }
    final previous = Set<String>.of(_titles);
    if (locked) {
      _titles.add(titleKey(item));
    } else {
      _titles.remove(titleKey(item));
    }
    try {
      await _save(_password, _locked);
    } catch (_) {
      _titles = previous;
      rethrow;
    }
    _unlockedTitles.remove(titleKey(item));
    notifyListeners();
  }

  bool unlockTitle(ContentItem item, String password) {
    if (!check(password)) return false;
    _unlockedTitles.add(titleKey(item));
    notifyListeners();
    return true;
  }

  Future<void> setTitleHidden(ContentItem item, bool value) async {
    await load();
    final previous = Set<String>.of(_hiddenTitles);
    if (value) {
      _hiddenTitles.add(titleKey(item));
    } else {
      _hiddenTitles.remove(titleKey(item));
    }
    try {
      await _save(_password, _locked);
    } catch (_) {
      _hiddenTitles = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setHidden(Category category, bool value) async {
    await load();
    final previous = Set<String>.of(_hidden);
    if (value) {
      _hidden.add(key(category));
    } else {
      _hidden.remove(key(category));
    }
    try {
      await _save(_password, _locked);
    } catch (_) {
      _hidden = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<List<ContentItem>> visibleItems(List<ContentItem> items) async {
    await load();
    return items.where((item) {
      if (titleHidden(item)) return false;
      if (item.categoryId != null &&
          hidden(Category(item.categoryId!, '', item.type))) {
        return false;
      }
      if (!hasLocks(item.type)) return true;
      if (item.categoryId == null) return false;
      return !isLocked(Category(item.categoryId!, '', item.type));
    }).toList();
  }
}
