import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../domain/trailer_movie.dart';
import '../data/tmdb_cast_service.dart';
import 'category_locks.dart';
import 'recent_catalog_cache.dart';

bool trailerTitleMatches(ContentItem item, TrailerMovie movie) {
  if (item.type != ContentType.movies || movie.release == null) return false;
  final year =
      item.releaseYear ??
      int.tryParse(
        RegExp(r'[\[(]((?:19|20)\d{2})[\])]').firstMatch(item.name)?.group(1) ??
            '',
      );
  return year == movie.release!.year &&
      [movie.title, movie.originalTitle]
          .where((s) => s.trim().isNotEmpty)
          .map(catalogMovieTitle)
          .contains(catalogMovieTitle(item.name));
}

bool trailerMetadataMatches(MediaDetails details, TrailerMovie movie) {
  if (!trailerTitleMatches(details.item, movie)) return false;
  // Require corroboration beyond a same-name, same-year title.
  final cast = details.cast.toLowerCase();
  if (movie.cast.any(
    (actor) => actor.name.isNotEmpty && cast.contains(actor.name.toLowerCase()),
  )) {
    return true;
  }
  final minutes = int.tryParse(details.duration);
  return movie.runtime > 0 &&
      minutes != null &&
      (minutes - movie.runtime).abs() <= 5;
}

String catalogMovieTitle(String title) {
  const languages =
      r'(?:english|hindi|urdu|tamil|telugu|malayalam|kannada|bengali|punjabi|spanish|arabic|korean|japanese|french|german|italian|portuguese|russian|chinese|turkish|dual audio|multi audio)';
  var value = title.trim();
  for (var i = 0; i < 4; i++) {
    value = value.replaceFirst(
      RegExp(
        r'\s*[\[(]\s*' + languages + r'(?:\s+dubbed)?\s*[\])]\s*$',
        caseSensitive: false,
      ),
      '',
    );
    value = value.replaceFirst(
      RegExp(
        r'\s*[-|:]\s*' + languages + r'(?:\s+dubbed)?\s*$',
        caseSensitive: false,
      ),
      '',
    );
    value = TmdbCastService.cleanTitle(value);
  }
  return TmdbCastService.normalize(value);
}

/// Conservative title+year matching. Ambiguous quality/language versions are
/// offered individually and always retain their original provider IDs.
Future<List<ContentItem>> matchTrailerMovie(
  IptvProvider provider,
  TrailerMovie movie,
) async {
  if (!provider.supportedTypes.contains(ContentType.movies) ||
      movie.release == null) {
    return [];
  }
  final locks = CategoryLocks.forProvider(provider);
  final catalog = await RecentCatalogCache.loadAll(
    provider,
    ContentType.movies,
  );
  final visible = await locks.visibleItems(
    catalog,
    excludeConfiguredLocks: true,
  );
  final titles = [
    movie.title,
    movie.originalTitle,
  ].where((s) => s.isNotEmpty).map((s) => catalogMovieTitle(s)).toSet();
  return visible.where((item) {
    final year =
        item.releaseYear ??
        int.tryParse(
          RegExp(
                r'[\[(]((?:19|20)\d{2})[\])]',
              ).firstMatch(item.name)?.group(1) ??
              '',
        );
    return year == movie.release!.year &&
        titles.contains(catalogMovieTitle(item.name));
  }).toList();
}
