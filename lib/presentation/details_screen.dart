import 'package:flutter/material.dart';
import '../application/watch_history.dart';
import 'smooth_page_route.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'player_screen.dart';
import 'widgets.dart';
import 'cinematic_series_details.dart';
import 'cinematic_movie_details.dart';

class DetailsScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentItem item;
  final bool autoPlay;
  final Episode? initialEpisode;
  final Future<SeriesDetails>? initialSeriesDetails;
  final Future<MediaDetails>? initialMovieDetails;
  const DetailsScreen({
    super.key,
    required this.provider,
    required this.item,
    this.autoPlay = false,
    this.initialEpisode,
    this.initialSeriesDetails,
    this.initialMovieDetails,
  });
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late Future<(MediaDetails, List<Episode>)> details;
  int? season;
  Episode? episode;
  bool resolving = false;
  bool autoPlayStarted = false;
  WatchEntry? previous;
  late final history = WatchHistory.forProvider(widget.provider);
  @override
  void initState() {
    super.initState();
    history.addListener(progressChanged);
    details = load();
  }

  Future<void> progressChanged() async {
    final saved = await history.latest(widget.item, episode: episode);
    if (mounted) setState(() => previous = saved);
  }

  @override
  void dispose() {
    history.removeListener(progressChanged);
    super.dispose();
  }

  Future<(MediaDetails, List<Episode>)> load({bool refresh = false}) async {
    previous = await history.latest(widget.item);
    if (widget.item.type == ContentType.series) {
      final result = await (refresh
          ? widget.provider.getSeriesDetails(widget.item)
          : widget.initialSeriesDetails ??
                widget.provider.getSeriesDetails(widget.item));
      for (final entry in result.episodes) {
        if (entry.id == previous?.episode?.id) {
          episode = entry;
          season = entry.season;
          break;
        }
      }
      final ordered = List<Episode>.of(result.episodes)
        ..sort(
          (a, b) => a.season == b.season
              ? a.number.compareTo(b.number)
              : a.season.compareTo(b.season),
        );
      return (result.details, ordered);
    }
    return (
      await (refresh
          ? widget.provider.getMovieDetails(widget.item)
          : widget.initialMovieDetails ??
                widget.provider.getMovieDetails(widget.item)),
      <Episode>[],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<(MediaDetails, List<Episode>)>(
      future: details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.item.type == ContentType.series
              ? const SeriesDetailsSkeleton()
              : const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            widget.item.type == ContentType.series
                ? 'Unable to load episodes'
                : safeMessage(snapshot.error!),
            action: () => setState(() {
              details = load(refresh: true);
            }),
          );
        }
        final (info, episodes) = snapshot.data!;
        if (widget.autoPlay &&
            !autoPlayStarted &&
            widget.item.type == ContentType.movies) {
          autoPlayStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) play(info.item, null, const [], artwork: info.artwork);
          });
        }
        if (widget.autoPlay && !autoPlayStarted && episodes.isNotEmpty) {
          autoPlayStarted = true;
          final targetId = widget.initialEpisode?.id ?? previous?.episode?.id;
          final target =
              episodes.where((entry) => entry.id == targetId).firstOrNull ??
              episodes.first;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              play(info.item, target, episodes, artwork: info.artwork);
            }
          });
        }
        if (widget.item.type == ContentType.series) {
          return CinematicSeriesDetails(
            provider: widget.provider,
            info: info,
            episodes: episodes,
            resolving: resolving,
            onPlay: (selected, restart) => play(
              info.item,
              selected,
              episodes,
              artwork: info.artwork,
              fromBeginning: restart,
            ),
          );
        }
        return CinematicMovieDetails(
          provider: widget.provider,
          info: info,
          previous: previous,
          resolving: resolving,
          onPlay: (restart) => play(
            info.item,
            null,
            const [],
            artwork: info.artwork,
            fromBeginning: restart,
          ),
        );
      },
    ),
  );

  Future<void> play(
    ContentItem item,
    Episode? selected,
    List<Episode> episodes, {
    Uri? artwork,
    bool fromBeginning = false,
  }) async {
    setState(() => resolving = true);
    try {
      Episode? current = selected;
      var startOver = fromBeginning;
      while (mounted) {
        final saved = await history.latest(item, episode: current);
        final resumePosition = startOver
            ? Duration.zero
            : saved?.position ?? Duration.zero;
        startOver = false;
        final source = await widget.provider.resolvePlayback(
          item,
          episode: current,
        );
        if (!mounted) return;
        final index = current == null
            ? -1
            : episodes.indexWhere((entry) => entry.id == current!.id);
        final next = index >= 0 && index + 1 < episodes.length
            ? episodes[index + 1]
            : null;
        final playbackMetadata = (await details).$1;
        if (!mounted) return;
        final route = SmoothPageRoute<Episode>(
          builder: (_) => PlayerScreen(
            source: source,
            provider: widget.provider,
            metadata: playbackMetadata,
            history: history,
            item: item,
            episode: current,
            nextEpisode: next,
            episodes: episodes,
            seriesArtwork: artwork,
            resumeAt: resumePosition,
            initialFullscreen: item.type != ContentType.live,
          ),
        );
        final requested = await Navigator.of(context).push(route);
        // Allow the previous screen/player to close before opening the next stream.
        await route.completed;
        if (!mounted || requested == null) break;
        current = requested;
        setState(() {
          episode = requested;
          season = requested.season;
        });
      }
      previous = await history.latest(item);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    } finally {
      if (mounted) setState(() => resolving = false);
    }
  }
}
