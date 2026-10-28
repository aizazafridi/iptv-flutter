import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/tmdb_artwork_service.dart';
import '../domain/models.dart';

class EpisodeArtwork extends StatefulWidget {
  final MediaDetails info;
  final Episode episode;
  final Uri? backdrop;
  final TmdbArtworkService? service;
  const EpisodeArtwork({
    super.key,
    required this.info,
    required this.episode,
    this.backdrop,
    this.service,
  });
  @override
  State<EpisodeArtwork> createState() => _EpisodeArtworkState();
}

class _EpisodeArtworkState extends State<EpisodeArtwork> {
  Timer? deadline;
  bool loaded = false, stalled = false;
  Future<Uri?>? still;
  @override
  void initState() {
    super.initState();
    startDeadline();
  }

  void startDeadline() {
    deadline?.cancel();
    loaded = false;
    stalled = false;
    if (widget.episode.artwork != null) {
      deadline = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && !loaded) setState(() => stalled = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant EpisodeArtwork old) {
    super.didUpdateWidget(old);
    if (old.info.item.id != widget.info.item.id ||
        old.episode.id != widget.episode.id ||
        old.service != widget.service) {
      still = null;
      startDeadline();
    }
  }

  @override
  void dispose() {
    deadline?.cancel();
    super.dispose();
  }

  Widget placeholder() => const ColoredBox(
    color: Color(0xff151d28),
    child: Center(child: Icon(Icons.tv, color: Colors.white38)),
  );
  Widget image(Uri uri, Widget Function() error) => CachedNetworkImage(
    imageUrl: uri.toString(),
    fit: BoxFit.cover,
    memCacheWidth: 600,
    maxWidthDiskCache: 600,
    placeholder: (_, _) => placeholder(),
    errorWidget: (_, _, _) => error(),
  );
  Widget backdrop() => widget.backdrop == null
      ? placeholder()
      : image(widget.backdrop!, placeholder);
  Widget fallback() {
    deadline?.cancel();
    return FutureBuilder<Uri?>(
      future: still ??= (widget.service ?? TmdbArtworkService.configured)
          .episodeStill(widget.info, widget.episode),
      builder: (_, snapshot) =>
          snapshot.data == null ? backdrop() : image(snapshot.data!, backdrop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.episode.artwork;
    if (provider == null || stalled) return fallback();
    return CachedNetworkImage(
      imageUrl: provider.toString(),
      fit: BoxFit.cover,
      memCacheWidth: 600,
      maxWidthDiskCache: 600,
      imageBuilder: (_, image) {
        loaded = true;
        deadline?.cancel();
        return Image(image: image, fit: BoxFit.cover);
      },
      placeholder: (_, _) => placeholder(),
      errorWidget: (_, _, _) => fallback(),
    );
  }
}
