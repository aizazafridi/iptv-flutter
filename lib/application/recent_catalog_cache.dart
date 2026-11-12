import 'package:flutter/foundation.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'recent_items.dart';
import 'dart:async';
import 'trailer_reminders.dart';

/// Cache belongs to the connected provider, so accounts never share catalogues.
class RecentCatalogCache {
  static final _revisions = Expando<ValueNotifier<int>>();
  static ValueNotifier<int> revision(IptvProvider provider) =>
      _revisions[provider] ??= ValueNotifier(0);
  static final _cache = Expando<Map<ContentType, Future<List<ContentItem>>>>();
  static Future<List<ContentItem>>? peek(
    IptvProvider provider,
    ContentType type,
  ) => _cache[provider]?[type];
  static final _all = Expando<Map<ContentType, Future<List<ContentItem>>>>();
  static Future<List<ContentItem>>? peekAll(
    IptvProvider provider,
    ContentType type,
  ) => _all[provider]?[type];
  static Future<List<ContentItem>> loadAll(
    IptvProvider provider,
    ContentType type,
  ) {
    final entries = _all[provider] ??= {};
    return entries.putIfAbsent(type, () async {
      try {
        final items = await provider.getAllItems(type);
        if (type == ContentType.movies) {
          unawaited(
            TrailerReminders.forProvider(
              provider,
            ).checkCatalog(provider, items).catchError((Object _) {}),
          );
        }
        return items;
      } catch (_) {
        entries.remove(type);
        rethrow;
      }
    });
  }

  static void invalidate(IptvProvider provider) {
    _cache[provider]?.clear();
    _all[provider]?.clear();
    revision(provider).value++;
  }

  static Future<List<ContentItem>> load(
    IptvProvider provider,
    ContentType type, {
    bool refresh = false,
  }) {
    final entries = _cache[provider] ??= {};
    if (refresh) {
      entries.remove(type);
      _all[provider]?.remove(type);
      revision(provider).value++;
    }
    return entries.putIfAbsent(type, () async {
      try {
        return recentlyAdded(await loadAll(provider, type));
      } catch (_) {
        entries.remove(type);
        rethrow;
      }
    });
  }
}
