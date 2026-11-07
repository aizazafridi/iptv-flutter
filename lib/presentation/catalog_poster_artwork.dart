import 'artwork_retry.dart';
import 'artwork_visibility.dart';
import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
import '../domain/iptv_provider.dart';
import 'package:flutter/material.dart';
import '../data/tmdb_artwork_service.dart';
import '../domain/models.dart';

/// Only visible recommendation cards request a fallback, after provider failure.
class CatalogPosterArtwork extends StatefulWidget {
  /// Floating previews observe resolved URLs without initiating metadata lookup.
  static final resolvedRevision = ValueNotifier<int>(0);
  static Uri? cachedUri(ContentItem item, IptvProvider provider) {
    final key =
        '${identityHashCode(TmdbArtworkService.configured)}:${identityHashCode(provider)}:${item.type.name}:${item.id}:${item.name}:${item.artwork}';
    return _CatalogPosterArtworkState.resolvedFallbacks[key] ?? item.artwork;
  }

  final ContentItem item;
  final TmdbArtworkService? service;
  final IptvProvider? provider;
  const CatalogPosterArtwork({
    super.key,
    required this.item,
    this.service,
    this.provider,
  });
  @override
  State<CatalogPosterArtwork> createState() => _CatalogPosterArtworkState();
}

class _CatalogPosterArtworkState extends State<CatalogPosterArtwork> {
  static final resolvedFallbacks = <String, Uri>{};
  static final pendingFallbacks = <String, Future<Uri?>>{};
  String get artworkKey =>
      '${identityHashCode(widget.service ?? TmdbArtworkService.configured)}:${identityHashCode(widget.provider)}:${widget.item.type.name}:${widget.item.id}:${widget.item.name}:${widget.item.artwork}';
  Future<Uri?>? fallback;
  ArtworkRetryScope retries = ArtworkRetryScope();
  bool eligible = false, providerFailed = false;
  @override
  void dispose() {
    retries.dispose();
    super.dispose();
  }

  void visibility(bool value) {
    if (eligible == value) return;
    eligible = value;
    retries.dispose();
    retries = ArtworkRetryScope();
    fallback = null;
  }

  Future<Uri?> recoveringFallback() {
    final key = artworkKey;
    return retryArtwork<Uri?>(
      scope: retries,
      load: resolveFallback,
      usable: (value) => value != null,
      active: () => mounted && eligible && artworkKey == key,
    );
  }

  void providerFailure() {
    final key = artworkKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && key == artworkKey && !providerFailed) {
        setState(() => providerFailed = true);
      }
    });
  }

  Future<Uri?> resolveFallback() =>
      pendingFallbacks.putIfAbsent(artworkKey, () {
        final key = artworkKey;
        return lookupFallback().whenComplete(() {
          pendingFallbacks.remove(key);
        });
      });
  Future<Uri?> lookupFallback() async {
    final key = artworkKey;
    final item = widget.item;
    final provider = widget.provider;
    final cached = resolvedFallbacks[key];
    if (cached != null) return cached;
    final service = widget.service ?? TmdbArtworkService.configured;
    if (!service.client.enabled) return null;
    final poster = await service.poster(item);
    if (poster != null) {
      if (resolvedFallbacks.length >= 200) {
        resolvedFallbacks.remove(resolvedFallbacks.keys.first);
      }
      resolvedFallbacks[key] = poster;
      CatalogPosterArtwork.resolvedRevision.value++;
      return poster;
    }
    if (provider == null) return null;
    try {
      // Duplicate names need the provider's release year or TMDB ID; do not
      // guess between unrelated shows that happen to have the same name.
      final details = item.type == ContentType.series
          ? (await provider.getSeriesDetails(item)).details
          : await provider.getMovieDetails(item);
      final resolved = await service.detailsPoster(details);
      if (resolved != null) {
        if (resolvedFallbacks.length >= 200) {
          resolvedFallbacks.remove(resolvedFallbacks.keys.first);
        }
        resolvedFallbacks[key] = resolved;
        CatalogPosterArtwork.resolvedRevision.value++;
      }
      return resolved;
    } catch (_) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant CatalogPosterArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.type != widget.item.type ||
        oldWidget.item.name != widget.item.name ||
        oldWidget.item.artwork != widget.item.artwork ||
        oldWidget.service != widget.service ||
        oldWidget.provider != widget.provider) {
      retries.dispose();
      retries = ArtworkRetryScope();
      fallback = null;
      providerFailed = false;
    }
  }

  Widget placeholder() => const ColoredBox(
    color: Color(0xff202833),
    child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38)),
  );
  Widget tmdb() => !eligible
      ? placeholder()
      : FutureBuilder<Uri?>(
          future: fallback ??= recoveringFallback(),
          builder: (context, snapshot) => snapshot.data == null
              ? placeholder()
              : SharedArtworkImage(
                  kind: ArtworkKind.poster,
                  imageUrl: snapshot.data.toString(),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (_, _) => placeholder(),
                  errorWidget: (_, _, _) => placeholder(),
                ),
        );
  @override
  Widget build(BuildContext context) => ArtworkVisibility(
    builder: (context, visible) {
      visibility(visible);
      final image = widget.item.artwork;
      if (image == null ||
          !['http', 'https'].contains(image.scheme) ||
          image.host.isEmpty) {
        return tmdb();
      }
      if (providerFailed || resolvedFallbacks.containsKey(artworkKey)) {
        return tmdb();
      }
      return SharedArtworkImage(
        kind: ArtworkKind.poster,
        imageUrl: image.toString(),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => placeholder(),
        errorWidget: (_, _, _) {
          providerFailure();
          return tmdb();
        },
      );
    },
  );
}

/// Shares already resolved artwork only: never calls a provider or metadata API.
class CachedPosterPreviewArtwork extends StatelessWidget {
  final ContentItem item;
  final IptvProvider provider;
  const CachedPosterPreviewArtwork({
    super.key,
    required this.item,
    required this.provider,
  });
  Widget placeholder() => const ColoredBox(
    color: Color(0xff202833),
    child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38)),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: CatalogPosterArtwork.resolvedRevision,
    builder: (_, _) {
      final uri = CatalogPosterArtwork.cachedUri(item, provider);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        return placeholder();
      }
      return SharedArtworkImage(
        kind: ArtworkKind.poster,
        imageUrl: uri.toString(),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (_, _) => placeholder(),
        errorWidget: (_, _, _) => placeholder(),
      );
    },
  );
}
