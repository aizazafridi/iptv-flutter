import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'recent_items.dart';

/// Cache belongs to the connected provider, so accounts never share catalogues.
class RecentCatalogCache {
  static final _cache = Expando<Map<ContentType, Future<List<ContentItem>>>>();
  static void invalidate(IptvProvider provider) => _cache[provider]?.clear();
  static Future<List<ContentItem>> load(
    IptvProvider provider,
    ContentType type, {
    bool refresh = false,
  }) {
    final entries = _cache[provider] ??= {};
    if (refresh) entries.remove(type);
    return entries.putIfAbsent(type, () async {
      try {
        return recentlyAdded(await provider.getAllItems(type));
      } catch (_) {
        entries.remove(type);
        rethrow;
      }
    });
  }
}
