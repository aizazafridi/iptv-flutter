import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import 'watch_history.dart';

class MyList extends ChangeNotifier {
  static final _instances = Expando<MyList>();
  static MyList forProvider(IptvProvider provider) =>
      _instances[provider] ??= MyList(WatchHistory.forProvider(provider).scope);
  final String scope;
  final FlutterSecureStorage storage;
  MyList(this.scope, {this.storage = const FlutterSecureStorage()});
  List<ContentItem> _items = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> load() => _loading ??= () async {
    final saved = await storage.read(key: 'my_list:$scope');
    if (saved != null) {
      _items = (jsonDecode(saved) as List).map((raw) {
        final row = raw as Map<String, dynamic>;
        return ContentItem(
          id: row['id'],
          name: row['name'],
          type: ContentType.values.byName(row['type']),
          artwork: row['artwork'] == null ? null : Uri.tryParse(row['artwork']),
          extension: row['extension'],
          categoryId: row['categoryId'],
        );
      }).toList();
    }
    notifyListeners();
  }();
  bool contains(ContentItem item) =>
      _items.any((saved) => saved.id == item.id && saved.type == item.type);
  Future<List<ContentItem>> items(ContentType type) async {
    await load();
    return _items.where((item) => item.type == type).toList();
  }

  Future<void> toggle(ContentItem item) async {
    await load();
    final write = _writes.then((_) async {
      final updated = List<ContentItem>.from(_items);
      if (contains(item)) {
        updated.removeWhere(
          (saved) => saved.id == item.id && saved.type == item.type,
        );
      } else {
        updated.insert(0, item);
      }
      final payload = jsonEncode(
        updated
            .map(
              (saved) => {
                'id': saved.id,
                'name': saved.name,
                'type': saved.type.name,
                'artwork': saved.artwork?.toString(),
                'extension': saved.extension,
                'categoryId': saved.categoryId,
              },
            )
            .toList(),
      );
      await storage.write(key: 'my_list:$scope', value: payload);
      _items = updated;
      notifyListeners();
    });
    _writes = write.catchError((_) {});
    await write;
  }
}
