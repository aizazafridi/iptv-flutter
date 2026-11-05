import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
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
  Future<Uri?>? still;
  @override
  void didUpdateWidget(covariant EpisodeArtwork old) {
    super.didUpdateWidget(old);
    if (old.info.item.id != widget.info.item.id ||
        old.episode.id != widget.episode.id ||
        old.service != widget.service) {
      still = null;
    }
  }

  Widget placeholder() => const ColoredBox(
    color: Color(0xff151d28),
    child: Center(child: Icon(Icons.tv, color: Colors.white38)),
  );
  Widget image(Uri uri, Widget Function() error) => SharedArtworkImage(
    kind: ArtworkKind.episode,
    imageUrl: uri.toString(),
    fit: BoxFit.cover,
    placeholder: (_, _) => placeholder(),
    errorWidget: (_, _, _) => error(),
  );
  Widget backdrop() => widget.backdrop == null
      ? placeholder()
      : image(widget.backdrop!, placeholder);
  Widget fallback() {
    return FutureBuilder<Uri?>(
      future: still ??= (widget.service ?? TmdbArtworkService.configured)
          .episodeStill(widget.info, widget.episode),
      builder: (_, snapshot) => snapshot.connectionState != ConnectionState.done
          ? placeholder()
          : snapshot.data == null
          ? backdrop()
          : image(snapshot.data!, backdrop),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.episode.artwork;
    if (provider == null) return fallback();
    return SharedArtworkImage(
      kind: ArtworkKind.episode,
      imageUrl: provider.toString(),
      fit: BoxFit.cover,
      placeholder: (_, _) => placeholder(),
      errorWidget: (_, _, _) => fallback(),
    );
  }
}
