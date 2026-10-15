import 'models.dart';

/// Optional capability, keeping alternative IPTV integrations independent.
abstract interface class EpgProvider {
  Future<List<EpgProgramme>> getEpg(ContentItem channel);
}

/// UI and application services depend on this contract, never provider JSON.
abstract interface class IptvProvider {
  String get displayName;
  Set<ContentType> get supportedTypes;
  Future<Account> connect();
  Future<List<Category>> getCategories(ContentType type);
  Future<List<ContentItem>> getItems(Category category);

  /// Return the full catalog for cross-category search.
  Future<List<ContentItem>> getAllItems(ContentType type);
  Future<MediaDetails> getMovieDetails(ContentItem movie);
  Future<SeriesDetails> getSeriesDetails(ContentItem series);
  Future<PlaybackSource> resolvePlayback(ContentItem item, {Episode? episode});
  void dispose();
}
