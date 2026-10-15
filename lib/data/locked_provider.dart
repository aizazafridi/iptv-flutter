import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../application/category_locks.dart';

/// Enforces locks in the API boundary, including search and playback entry points.
class LockedProvider implements IptvProvider, EpgProvider {
  final IptvProvider delegate;
  final CategoryLocks locks;
  final Map<ContentType, Future<List<ContentItem>>> _catalogs = {};
  LockedProvider(this.delegate, this.locks);
  @override
  String get displayName => delegate.displayName;
  @override
  Set<ContentType> get supportedTypes => delegate.supportedTypes;
  @override
  Future<Account> connect() async {
    await locks.load();
    return delegate.connect();
  }

  @override
  Future<List<Category>> getCategories(ContentType type) =>
      delegate.getCategories(type);
  @override
  Future<List<ContentItem>> getItems(Category category) async {
    await locks.load();
    if (locks.isLocked(category)) {
      throw const ProviderException(
        'This category is locked. Enter its password to access it.',
      );
    }
    return delegate.getItems(category);
  }

  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async =>
      locks.visibleItems(await delegate.getAllItems(type));
  Future<List<ContentItem>> visibleSavedItems(List<ContentItem> items) async {
    await locks.load();
    final resolved = <ContentItem>[];
    for (final item in items) {
      var categoryId = item.categoryId;
      if (categoryId == null && locks.hasLocks(item.type)) {
        try {
          final catalog = await _catalogs.putIfAbsent(
            item.type,
            () => delegate.getAllItems(item.type),
          );
          categoryId = catalog
              .where((entry) => entry.id == item.id)
              .firstOrNull
              ?.categoryId;
        } catch (_) {
          _catalogs.remove(item.type);
          rethrow;
        }
      }
      resolved.add(
        ContentItem(
          id: item.id,
          name: item.name,
          type: item.type,
          artwork: item.artwork,
          extension: item.extension,
          addedAt: item.addedAt,
          categoryId: categoryId,
        ),
      );
    }
    return locks.visibleItems(resolved);
  }

  Future<void> _checkItem(ContentItem item) async {
    await locks.load();
    if (!locks.hasLocks(item.type)) return;
    var categoryId = item.categoryId;
    if (categoryId == null) {
      final catalog = await delegate.getAllItems(item.type);
      categoryId = catalog
          .where((entry) => entry.id == item.id)
          .firstOrNull
          ?.categoryId;
    }
    if (categoryId == null ||
        locks.isLocked(Category(categoryId, '', item.type))) {
      throw const ProviderException(
        'This title belongs to a locked category. Unlock the category first.',
      );
    }
  }

  @override
  Future<MediaDetails> getMovieDetails(ContentItem movie) async {
    await _checkItem(movie);
    return delegate.getMovieDetails(movie);
  }

  @override
  Future<SeriesDetails> getSeriesDetails(ContentItem series) async {
    await _checkItem(series);
    return delegate.getSeriesDetails(series);
  }

  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    await _checkItem(item);
    return delegate.resolvePlayback(item, episode: episode);
  }

  @override
  Future<List<EpgProgramme>> getEpg(ContentItem channel) async {
    await _checkItem(channel);
    final provider = delegate;
    if (provider is! EpgProvider) return [];
    return (provider as EpgProvider).getEpg(channel);
  }

  @override
  void dispose() => delegate.dispose();
}
