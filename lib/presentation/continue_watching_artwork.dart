import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/tmdb_artwork_service.dart';
import '../domain/models.dart';

class ContinueWatchingArtwork extends StatefulWidget {
  final ContentItem item;
  final TmdbArtworkService? service;
  const ContinueWatchingArtwork({super.key, required this.item, this.service});
  @override
  State<ContinueWatchingArtwork> createState() =>
      _ContinueWatchingArtworkState();
}

class _ContinueWatchingArtworkState extends State<ContinueWatchingArtwork> {
  late Future<Uri?> backdrop = load();
  Future<Uri?> load() =>
      (widget.service ?? TmdbArtworkService.configured).backdrop(widget.item);
  @override
  void didUpdateWidget(covariant ContinueWatchingArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.type != widget.item.type ||
        oldWidget.item.name != widget.item.name) {
      backdrop = load();
    }
  }

  Widget poster() => ColoredBox(
    color: const Color(0xff101722),
    child: widget.item.artwork == null
        ? const Center(child: Icon(Icons.movie_outlined, color: Colors.white38))
        : CachedNetworkImage(
            imageUrl: widget.item.artwork.toString(),
            fit: BoxFit.contain,
            memCacheWidth: 480,
            maxWidthDiskCache: 480,
            errorWidget: (_, _, _) => const Center(
              child: Icon(Icons.movie_outlined, color: Colors.white38),
            ),
          ),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: backdrop,
    builder: (context, snapshot) {
      final uri = snapshot.data;
      if (uri == null) return poster();
      return CachedNetworkImage(
        imageUrl: uri.toString(),
        fit: BoxFit.cover,
        memCacheWidth: 480,
        maxWidthDiskCache: 780,
        placeholder: (_, _) => poster(),
        errorWidget: (_, _, _) => poster(),
      );
    },
  );
}
