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
  final Set<String> _unlocked = {};
  Future<void>? _loading;
  bool get hasPassword => _password.isNotEmpty;
  String key(Category category) => '${category.type.name}:${category.id}';
  bool configured(Category category) => _locked.contains(key(category));
  bool isLocked(Category category) =>
      configured(category) && !_unlocked.contains(key(category));
  bool hasLocks(ContentType type) =>
      _locked.any((key) => key.startsWith('${type.name}:'));
  bool check(String password) => _password.isNotEmpty && password == _password;
  Future<void> load() => _loading ??= () async {
    final saved = await storage.read(key: 'category_locks:$scope');
    if (saved != null) {
      final value = jsonDecode(saved) as Map<String, dynamic>;
      _password = value['password'] as String? ?? '';
      _locked = (value['categories'] as List? ?? []).cast<String>().toSet();
    }
  }();
  Future<void> _save(String password, Set<String> locked) => storage.write(
    key: 'category_locks:$scope',
    value: jsonEncode({'password': password, 'categories': locked.toList()}),
  );
  Future<void> setPassword(String password, {String current = ''}) async {
    await load();
    if (hasPassword && !check(current)) {
      throw const ProviderException('Current lock password is incorrect.');
    }
    if (password.length < 4) {
      throw const ProviderException(
        'Use at least four characters for the lock password.',
      );
    }
    await _save(password, _locked);
    _password = password;
    _unlocked.clear();
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

  bool unlock(Category category, String password) {
    if (!check(password)) return false;
    _unlocked.add(key(category));
    notifyListeners();
    return true;
  }

  Future<List<ContentItem>> visibleItems(List<ContentItem> items) async {
    await load();
    return items.where((item) {
      if (!hasLocks(item.type)) return true;
      if (item.categoryId == null) return false;
      return !isLocked(Category(item.categoryId!, '', item.type));
    }).toList();
  }
}
