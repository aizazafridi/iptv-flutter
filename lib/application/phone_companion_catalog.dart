import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'category_locks.dart';
import 'my_list.dart';
import 'recent_catalog_cache.dart';
import 'universal_search.dart';
import 'phone_companion_server.dart';

class PhoneCompanionCatalog {
  final IptvProvider provider;
  final Future<void> Function(ContentItem, bool) onOpen;
  final bool Function() isActive;
  PhoneCompanionCatalog(
    this.provider, {
    required this.onOpen,
    required this.isActive,
  });
  late final locks = CategoryLocks.forProvider(provider);
  late final saved = MyList.forProvider(provider);
  void checkActive() {
    if (!isActive()) {
      throw const CompanionError(401, 'Profile changed. Pair again.');
    }
  }

  ContentType type(Map<String, dynamic> body) {
    final value = body['type'];
    final result = ContentType.values.where((t) => t.name == value).firstOrNull;
    if (result == null || !provider.supportedTypes.contains(result)) {
      throw const CompanionError(400, 'Choose Live TV, Movies or Series.');
    }
    return result;
  }

  Future<List<ContentItem>> visible(ContentType type) async {
    final rows = await RecentCatalogCache.loadAll(provider, type);
    final allowed = await locks.visibleItems(
      rows,
      excludeConfiguredLocks: true,
    );
    checkActive();
    return allowed;
  }

  Future<ContentItem> item(Map<String, dynamic> body) async {
    final rows = await visible(type(body));
    final match = rows.where((r) => r.id == body['id']).firstOrNull;
    if (match == null) {
      throw const CompanionError(
        404,
        'This title is unavailable or restricted in this profile.',
      );
    }
    return match;
  }

  Map<String, Object?> json(ContentItem item) => {
    'id': item.id,
    'name': item.name,
    'type': item.type.name,
    'saved': saved.contains(item),
    if (item.type == ContentType.live) ...{
      'groups': saved.groups.memberships(item.id).toList(),
      'general': saved.groups.generalContains(
        item.id,
        saved: saved.contains(item),
      ),
    },
  };
  String text(Object? value, {int max = 100}) {
    if (value is! String || value.length > max) {
      throw const CompanionError(400, 'Invalid text.');
    }
    return value.trim();
  }

  Future<Object> dispatch(String path, Map<String, dynamic> body) async {
    checkActive();
    await saved.load();
    checkActive();
    if (path == '/status') {
      return {'types': provider.supportedTypes.map((t) => t.name).toList()};
    }
    if (path == '/groups') {
      return {
        'groups': saved.groups.groups
            .map((g) => {'id': g.id, 'name': g.name})
            .toList(),
      };
    }
    if (path == '/group') {
      switch (body['action']) {
        case 'create':
          await saved.groups.create(text(body['name'], max: 40));
        case 'rename':
          await saved.groups.rename(
            text(body['id']),
            text(body['name'], max: 40),
          );
        case 'delete':
          await saved.groups.delete(text(body['id']));
        default:
          throw const CompanionError(400, 'Unknown group action.');
      }
      return {'ok': true};
    }
    if (path == '/search' || path == '/list') {
      final kind = type(body);
      final rows = await visible(kind);
      List<ContentItem> result;
      if (path == '/list') {
        result = rows.where(saved.contains).toList();
      } else {
        final query = text(body['query'] ?? '', max: 100);
        final source = RecentCatalogCache.loadAll(provider, kind);
        final index = await SearchIndex.forCatalog(provider, kind, source);
        result = query.isEmpty
            ? rows
            : await index.search(query, allowed: rows.map((r) => r.id).toSet());
      }
      checkActive();
      final rawOffset = body['offset'] ?? 0;
      if (rawOffset is! int || rawOffset < 0 || rawOffset > 100000) {
        throw const CompanionError(400, 'Invalid page.');
      }
      return {
        'items': result.skip(rawOffset).take(40).map(json).toList(),
        'more': result.length > rawOffset + 40,
        'types': provider.supportedTypes.map((t) => t.name).toList(),
      };
    }
    final selected = await item(
      body,
    ); // Always resolve a canonical, currently allowed ID.
    checkActive();
    if (path == '/favourite') {
      if (body['saved'] is! bool) {
        throw const CompanionError(400, 'Choose add or remove.');
      }
      if (saved.contains(selected) != body['saved']) {
        await saved.toggle(selected);
      }
      return json(selected);
    }
    if (path == '/membership') {
      if (selected.type != ContentType.live ||
          body['groups'] is! List ||
          body['general'] is! bool) {
        throw const CompanionError(400, 'Invalid channel groups.');
      }
      final ids = (body['groups'] as List).whereType<String>().toSet();
      if (ids.length != (body['groups'] as List).length ||
          ids.length > 100 ||
          ids.any((id) => !saved.groups.groups.any((g) => g.id == id))) {
        throw const CompanionError(
          400,
          'A selected group is no longer available.',
        );
      }
      await saved.saveLiveMembership(
        selected,
        ids,
        general: body['general'] as bool,
      );
      return json(selected);
    }
    if (path == '/open') {
      if (body['play'] != null && body['play'] is! bool) {
        throw const CompanionError(400, 'Invalid playback action.');
      }
      await onOpen(selected, body['play'] == true);
      return {'ok': true};
    }
    throw const CompanionError(404, 'Unknown action.');
  }
}
