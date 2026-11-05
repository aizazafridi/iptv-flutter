import 'live_favourite_groups.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import 'watch_history.dart';

class MyList extends ChangeNotifier {
  static final _instances = Expando<MyList>();
  static MyList forProvider(IptvProvider provider) =>
      _instances[provider] ??= MyList(
        WatchHistory.forProvider(provider).scope,
        groups: LiveFavouriteGroups.forProvider(provider),
      );
  final LiveFavouriteGroups groups;
  final String scope;
  final FlutterSecureStorage storage;
  MyList(
    this.scope, {
    this.storage = const FlutterSecureStorage(),
    LiveFavouriteGroups? groups,
  }) : groups = groups ?? LiveFavouriteGroups(scope, storage: storage) {
    this.groups.addListener(notifyListeners);
  }
  @override
  void dispose() {
    groups.removeListener(notifyListeners);
    super.dispose();
  }

  List<ContentItem> _items = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> load() => _loading ??= () async {
    await groups.recoverPending();
    await groups.load();
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
      _items.any((saved) => saved.id == item.id && saved.type == item.type) &&
      (item.type != ContentType.live ||
          groups.hasMembership(item.id, saved: true));
  Future<List<ContentItem>> items(ContentType type) async {
    await load();
    return _items.where((item) => item.type == type && contains(item)).toList();
  }

  Future<void> saveLiveMembership(
    ContentItem item,
    Set<String> selected, {
    required bool general,
  }) async {
    await load();
    final desired = Set<String>.of(selected);
    final write = _writes.then((_) async {
      final existing = groups.memberships(item.id);
      final originalGeneral = groups.generalContains(
        item.id,
        saved: contains(item),
      );
      if (originalGeneral == general &&
          setEquals(existing, desired) &&
          contains(item) == (general || desired.isNotEmpty)) {
        return;
      }
      final updated = _items
          .where((row) => row.id != item.id || row.type != item.type)
          .toList();
      if (general || desired.isNotEmpty) {
        final previous = _items.indexWhere(
          (row) => row.id == item.id && row.type == item.type,
        );
        updated.insert(
          previous < 0 ? 0 : previous.clamp(0, updated.length),
          item,
        );
      }
      final payload = jsonEncode(updated.map(_jsonItem).toList());
      await groups.commitMembership(item.id, desired, general, (
        groupPayload,
      ) async {
        final previousGroups = await storage.read(key: groups.key);
        final previousList = await storage.read(key: 'my_list:$scope');
        await storage.write(
          key: groups.transactionKey,
          value: jsonEncode({'groups': previousGroups, 'list': previousList}),
        );
        try {
          await storage.write(key: groups.key, value: groupPayload);
          await storage.write(key: 'my_list:$scope', value: payload);
          await storage.delete(key: groups.transactionKey);
        } catch (_) {
          for (final entry in {
            groups.key: previousGroups,
            'my_list:$scope': previousList,
          }.entries) {
            if (entry.value == null) {
              await storage.delete(key: entry.key);
            } else {
              await storage.write(key: entry.key, value: entry.value);
            }
          }
          await storage.delete(key: groups.transactionKey);
          rethrow;
        }
      });
      _items = updated;
      notifyListeners();
    });
    _writes = write.catchError((_) {});
    await write;
  }

  Map<String, dynamic> _jsonItem(ContentItem item) => {
    'id': item.id,
    'name': item.name,
    'type': item.type.name,
    'artwork': item.artwork?.toString(),
    'extension': item.extension,
    'categoryId': item.categoryId,
  };
  Future<void> toggle(ContentItem item) async {
    await load();
    if (item.type == ContentType.live) {
      final removing = contains(item);
      return saveLiveMembership(
        item,
        removing ? {} : groups.memberships(item.id),
        general: !removing,
      );
    }
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
      final removing = item.type == ContentType.live && contains(item);
      Set<String> previousGroups = {};
      if (removing) {
        await groups.load();
        previousGroups = groups.memberships(item.id);
        await groups.assign(item.id, {});
      }
      try {
        await storage.write(key: 'my_list:$scope', value: payload);
      } catch (_) {
        if (removing) await groups.assign(item.id, previousGroups);
        rethrow;
      }
      _items = updated;
      notifyListeners();
    });
    _writes = write.catchError((_) {});
    await write;
  }
}
