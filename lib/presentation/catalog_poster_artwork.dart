import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../domain/iptv_provider.dart';
import 'package:flutter/material.dart';
import '../data/tmdb_artwork_service.dart';
import '../domain/models.dart';

/// Only visible recommendation cards request a fallback, after provider failure.
class CatalogPosterArtwork extends StatefulWidget {
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
  static final slowHosts = <String>{};
  static final resolvedFallbacks = <String, Uri>{};
  String get artworkKey =>
      '${identityHashCode(widget.service ?? TmdbArtworkService.configured)}:${identityHashCode(widget.provider)}:${widget.item.type.name}:${widget.item.id}:${widget.item.name}';
  Future<Uri?>? fallback;
  Timer? deadline;
  bool loaded = false, stalled = false;
  @override
  void initState() {
    super.initState();
    startDeadline();
  }

  Future<void> restoreCachedFallback() async {
    final key = artworkKey;
    final uri = await (widget.service ?? TmdbArtworkService.configured)
        .cachedPoster(widget.item);
    if (mounted && artworkKey == key && !loaded && uri != null) {
      setState(() {
        fallback = Future.value(uri);
        stalled = true;
      });
    }
  }

  void startDeadline() {
    unawaited(restoreCachedFallback());
    deadline?.cancel();
    loaded = false;
    stalled = resolvedFallbacks.containsKey(artworkKey);
    if (widget.item.artwork != null) {
      deadline = Timer(
        slowHosts.contains(widget.item.artwork!.host)
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 1500),
        () {
          if (mounted && !loaded) {
            if (slowHosts.length >= 32) slowHosts.remove(slowHosts.first);
            slowHosts.add(widget.item.artwork!.host);
            setState(() => stalled = true);
          }
        },
      );
    }
  }

  @override
  void dispose() {
    deadline?.cancel();
    super.dispose();
  }

  Future<Uri?> resolveFallback() async {
    final cached = resolvedFallbacks[artworkKey];
    if (cached != null) return cached;
    final service = widget.service ?? TmdbArtworkService.configured;
    if (!service.client.enabled) return null;
    final poster = await service.poster(widget.item);
    if (poster != null) {
      if (resolvedFallbacks.length >= 200) {
        resolvedFallbacks.remove(resolvedFallbacks.keys.first);
      }
      resolvedFallbacks[artworkKey] = poster;
      return poster;
    }
    if (widget.provider == null) return null;
    try {
      // Duplicate names need the provider's release year or TMDB ID; do not
      // guess between unrelated shows that happen to have the same name.
      final details = widget.item.type == ContentType.series
          ? (await widget.provider!.getSeriesDetails(widget.item)).details
          : await widget.provider!.getMovieDetails(widget.item);
      final resolved = await service.detailsPoster(details);
      if (resolved != null) {
        if (resolvedFallbacks.length >= 200) {
          resolvedFallbacks.remove(resolvedFallbacks.keys.first);
        }
        resolvedFallbacks[artworkKey] = resolved;
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
        oldWidget.service != widget.service ||
        oldWidget.provider != widget.provider) {
      fallback = null;
      startDeadline();
    }
  }

  Widget placeholder() => const ColoredBox(
    color: Color(0xff202833),
    child: Center(child: Icon(Icons.movie_outlined, color: Colors.white38)),
  );
  Widget tmdb() => FutureBuilder<Uri?>(
    future: fallback ??= resolveFallback(),
    builder: (context, snapshot) => snapshot.data == null
        ? placeholder()
        : CachedNetworkImage(
            imageUrl: snapshot.data.toString(),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: 342,
            maxWidthDiskCache: 342,
            placeholder: (_, _) => placeholder(),
            errorWidget: (_, _, _) => placeholder(),
          ),
  );
  @override
  Widget build(BuildContext context) {
    final image = widget.item.artwork;
    if (image == null ||
        !['http', 'https'].contains(image.scheme) ||
        image.host.isEmpty) {
      return tmdb();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (stalled) tmdb(),
        CachedNetworkImage(
          imageUrl: image.toString(),
          imageBuilder: (context, provider) {
            loaded = true;
            deadline?.cancel();
            return Image(
              image: provider,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            );
          },
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          memCacheWidth: 342,
          maxWidthDiskCache: 342,
          placeholder: (_, _) =>
              stalled ? const SizedBox.expand() : placeholder(),
          errorWidget: (_, _, _) => tmdb(),
        ),
      ],
    );
  }
}
