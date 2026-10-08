import '../domain/iptv_provider.dart';
import '../domain/models.dart';

/// A provider-scoped session cache. No provider-specific fields or HTTP in search.
class CatalogIndex {
  static final _instances = Expando<CatalogIndex>();
  static CatalogIndex forProvider(IptvProvider provider) =>
      _instances[provider] ??= CatalogIndex(provider);
  final IptvProvider provider;
  CatalogIndex(this.provider);
  final Map<String, String> _cast = {};
  final Map<String, Future<String>> _pending = {};
  final Set<String> failed = {};
  String key(ContentItem item) => '${item.type.name}:${item.id}';
  String castFor(ContentItem item) => _cast[key(item)] ?? item.cast ?? '';
  bool known(ContentItem item) =>
      _cast.containsKey(key(item)) || item.cast != null;

  bool matches(ContentItem item, String query) {
    final text = '${item.name} ${castFor(item)}'.toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }

  Future<String> _load(ContentItem item) {
    return _pending.putIfAbsent(key(item), () async {
      try {
        final details = item.type == ContentType.series
            ? (await provider.getSeriesDetails(item)).details
            : await provider.getMovieDetails(item);
        _cast[key(item)] = details.cast;
        failed.remove(key(item));
        return details.cast;
      } finally {
        _pending.remove(key(item));
      }
    });
  }

  /// Two workers limit provider load. Navigation/pausing stops new requests;
  /// already-running requests may finish and populate the reusable session cache.
  Future<void> enrich(
    List<ContentItem> items, {
    required bool Function() cancelled,
    required void Function() onProgress,
    bool retryFailed = false,
  }) async {
    final unique = <String, ContentItem>{
      for (final item in items) key(item): item,
    };
    final queue = unique.values
        .where(
          (item) =>
              !known(item) && (retryFailed || !failed.contains(key(item))),
        )
        .toList();
    var cursor = 0;
    Future<void> worker() async {
      while (!cancelled() && cursor < queue.length) {
        final item = queue[cursor++];
        try {
          await _load(item);
        } catch (_) {
          failed.add(key(item));
        }
        if (!cancelled()) onProgress();
      }
    }

    await Future.wait([worker(), worker()]);
  }
}
