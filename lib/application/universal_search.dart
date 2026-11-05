import 'dart:async';
import 'package:flutter/foundation.dart' hide Category;
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import 'category_locks.dart';
import 'recent_catalog_cache.dart';

String normalizeSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

class SearchIndex {
  final List<({ContentItem item, String title})> entries;
  SearchIndex._(this.entries);
  static final _cache =
      Expando<
        Map<
          ContentType,
          ({Future<List<ContentItem>> source, Future<SearchIndex> index})
        >
      >();
  static Future<SearchIndex> forCatalog(
    IptvProvider provider,
    ContentType type,
    Future<List<ContentItem>> source,
  ) {
    final cache = _cache[provider] ??= {};
    final previous = cache[type];
    if (identical(previous?.source, source)) return previous!.index;
    final future = source.then(build);
    cache[type] = (source: source, index: future);
    return future;
  }

  static Future<SearchIndex> build(List<ContentItem> items) async {
    final entries = <({ContentItem item, String title})>[];
    final ids = <String>{};
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      // Only duplicate IDs are collapsed. HD/4K/language versions retain their own IDs.
      if (ids.add('${item.type.name}:${item.id}')) {
        entries.add((item: item, title: normalizeSearch(item.name)));
      }
      if (i > 0 && i % 512 == 0) await Future<void>.delayed(Duration.zero);
    }
    return SearchIndex._(entries);
  }

  Future<List<ContentItem>> search(
    String query, {
    Set<String>? allowed,
    bool Function()? cancelled,
  }) async {
    final normalized = normalizeSearch(query);
    if (normalized.isEmpty) return [];
    final words = normalized.split(' ');
    final buckets = List.generate(4, (_) => <ContentItem>[]);
    for (var i = 0; i < entries.length; i++) {
      if (cancelled?.call() == true) return [];
      final entry = entries[i], title = entry.title;
      if (allowed == null || allowed.contains(entry.item.id)) {
        final rank = title == normalized
            ? 0
            : title.startsWith(normalized)
            ? 1
            : title.contains(normalized)
            ? 2
            : words.every(title.contains)
            ? 3
            : -1;
        if (rank >= 0) buckets[rank].add(entry.item);
      }
      // Yield regularly; no isolate is spawned per keystroke or query.
      if (i > 0 && i % 512 == 0) await Future<void>.delayed(Duration.zero);
    }
    return buckets.expand((bucket) => bucket).toList();
  }
}

class UniversalSearchController extends ChangeNotifier {
  static const order = [
    ContentType.series,
    ContentType.movies,
    ContentType.live,
  ];
  final IptvProvider provider;
  late final locks = CategoryLocks.forProvider(provider);
  final indexes = <ContentType, SearchIndex>{};
  final allowed = <ContentType, Set<String>>{};
  final results = <ContentType, List<ContentItem>>{};
  final loading = <ContentType>{}, errors = <ContentType>{};
  ContentType? filter;
  String query = '';
  bool searching = false, _disposed = false;
  Timer? debounce;
  int generation = 0, _queryVersion = 0;
  UniversalSearchController(this.provider) {
    RecentCatalogCache.revision(provider).addListener(reload);
    locks.addListener(reload);
  }
  bool get pending => searching || loading.isNotEmpty;
  void reload() {
    final version = ++generation;
    ++_queryVersion;
    indexes.clear();
    allowed.clear();
    results.clear();
    errors.clear();
    loading.clear();
    for (final type in order.where(provider.supportedTypes.contains)) {
      loading.add(type);
      unawaited(_load(type, version));
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _load(ContentType type, int version) async {
    try {
      final source = RecentCatalogCache.loadAll(provider, type);
      final index = await SearchIndex.forCatalog(provider, type, source);
      await locks.load();
      final visible = await locks.visibleItems(
        index.entries.map((e) => e.item).toList(),
      );
      if (_disposed || version != generation) return;
      indexes[type] = index;
      allowed[type] = visible
          .where(
            (item) =>
                locks.allowsItem(item) &&
                !locks.titleConfigured(item) &&
                (item.categoryId == null ||
                    !locks.configured(Category(item.categoryId!, '', type))),
          )
          .map((e) => e.id)
          .toSet();
    } catch (_) {
      if (!_disposed && version == generation) errors.add(type);
    }
    if (_disposed || version != generation) return;
    loading.remove(type);
    unawaited(_run());
  }

  void setQuery(String value, {bool immediate = false}) {
    debounce?.cancel();
    ++_queryVersion;
    void apply() {
      if (_disposed) return;
      query = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      unawaited(_run());
    }

    if (immediate) {
      apply();
    } else {
      debounce = Timer(const Duration(milliseconds: 300), apply);
    }
  }

  void setFilter(ContentType? type) {
    filter = type;
    if (!_disposed) notifyListeners();
  }

  Future<void> _run() async {
    final ticket = ++_queryVersion;
    results.clear();
    searching = query.isNotEmpty;
    notifyListeners();
    final copy = Map<ContentType, SearchIndex>.from(indexes);
    for (final type in order) {
      final index = copy[type];
      if (index == null) continue;
      List<ContentItem> matches;
      if (query.isEmpty) {
        matches =
            type == ContentType.live
                  ? []
                  : index.entries
                        .map((e) => e.item)
                        .where(
                          (item) =>
                              item.addedAt != null &&
                              allowed[type]!.contains(item.id),
                        )
                        .toList()
              ..sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
        matches = matches.take(20).toList();
      } else {
        matches = await index.search(
          query,
          allowed: allowed[type],
          cancelled: () => _disposed || ticket != _queryVersion,
        );
      }
      if (_disposed || ticket != _queryVersion) return;
      results[type] = matches;
      notifyListeners();
    }
    if (_disposed || ticket != _queryVersion) return;
    searching = false;
    notifyListeners();
  }

  List<ContentItem> get recent {
    final rows = results.entries
        .where((e) => filter == null || e.key == filter)
        .expand((e) => e.value)
        .toList();
    rows.sort(
      (a, b) =>
          (b.addedAt ?? DateTime(1970)).compareTo(a.addedAt ?? DateTime(1970)),
    );
    return rows.take(20).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    ++generation;
    ++_queryVersion;
    debounce?.cancel();
    RecentCatalogCache.revision(provider).removeListener(reload);
    locks.removeListener(reload);
    super.dispose();
  }
}
