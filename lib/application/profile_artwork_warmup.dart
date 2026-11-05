import 'dart:async';
import '../data/artwork_repository.dart';
import '../data/tmdb_artwork_service.dart';
import '../domain/models.dart';
import 'browsing_mode.dart';

/// A bounded first-screen batch, reusing the same URL variants and disk cache.
/// Never blocks login indefinitely and does not preload cast or whole catalogs.
Future<void> warmProfileArtwork(
  Iterable<ContentItem> items, {
  Duration budget = const Duration(seconds: 5),
  Future<Uri?> Function(ContentItem)? resolvePoster,
  Future<void> Function(String)? cacheImage,
}) async {
  if (BrowsingModeSettings.instance.lite) return;
  final owner = Object();
  final urls = <String>{};
  var active = true;
  Future<void> load(ContentItem item) async {
    try {
      var image = item.artwork;
      if (image == null ||
          !['http', 'https'].contains(image.scheme) ||
          image.host.isEmpty) {
        image = await (resolvePoster ?? TmdbArtworkService.configured.poster)(
          item,
        );
      }
      if (!active || BrowsingModeSettings.instance.lite || image == null) {
        return;
      }
      final url = ArtworkRepository.variant(
        image.toString(),
        ArtworkKind.poster,
      );
      if (!urls.add(url)) return;
      ArtworkRepository.demand(url, owner, ArtworkPriority.visible);
      if (cacheImage != null) {
        await cacheImage(url);
      } else {
        await ArtworkRepository.instance.getSingleFile(url);
      }
    } catch (_) {
      // Visible cards retain their existing automatic retry/fallback behavior.
    }
  }

  final pending = items.iterator;
  Future<void> worker() async {
    while (active &&
        !BrowsingModeSettings.instance.lite &&
        pending.moveNext()) {
      await load(pending.current);
    }
  }

  try {
    await Future.wait(List.generate(4, (_) => worker())).timeout(budget);
  } on TimeoutException {
    // Login remains usable even when an upstream image host is unavailable.
  } finally {
    active = false;
    for (final url in urls) {
      ArtworkRepository.release(url, owner);
    }
  }
}
