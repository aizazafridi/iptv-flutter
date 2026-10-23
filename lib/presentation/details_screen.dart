import 'package:flutter/material.dart';
import '../application/watch_history.dart';
import 'smooth_page_route.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'player_screen.dart';
import 'widgets.dart';
import 'my_list_button.dart';

class DetailsScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentItem item;
  const DetailsScreen({super.key, required this.provider, required this.item});
  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  late Future<(MediaDetails, List<Episode>)> details;
  int? season;
  Episode? episode;
  bool resolving = false;
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

  Future<(MediaDetails, List<Episode>)> load() async {
    previous = await history.latest(widget.item);
    if (widget.item.type == ContentType.series) {
      final result = await widget.provider.getSeriesDetails(widget.item);
      for (final entry in result.episodes) {
        if (entry.id == previous?.episode?.id) {
          episode = entry;
          season = entry.season;
          break;
        }
      }
      return (result.details, result.episodes);
    }
    return (await widget.provider.getMovieDetails(widget.item), <Episode>[]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item.name)),
    body: AsyncView(
      future: details,
      retry: () => setState(() => details = load()),
      builder: (result) {
        final (info, episodes) = result;
        final series = widget.item.type == ContentType.series;
        final seasons = episodes.map((e) => e.season).toSet().toList()..sort();
        final activeSeason = season ?? (seasons.isEmpty ? null : seasons.first);
        final visibleEpisodes = episodes
            .where((e) => e.season == activeSeason)
            .toList();
        final selected = episode != null && visibleEpisodes.contains(episode)
            ? episode
            : (visibleEpisodes.isEmpty ? null : visibleEpisodes.first);
        final canResume =
            previous != null &&
            (!series || selected?.id == previous?.episode?.id);
        final played = canResume ? previous!.position : Duration.zero;
        final length = canResume ? previous!.duration : Duration.zero;
        final remaining = ((length - played).inSeconds / 60).ceil().clamp(
          0,
          99999,
        );
        final metadata = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.item.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children:
                  [
                        info.genre,
                        info.releaseDate,
                        info.rating.isEmpty ? '' : '★ ${info.rating}',
                        info.duration,
                      ]
                      .where((text) => text.isNotEmpty)
                      .map((text) => Chip(label: Text(text)))
                      .toList(),
            ),
            const SizedBox(height: 16),
            Text(
              info.synopsis.isEmpty ? 'No synopsis available.' : info.synopsis,
              style: const TextStyle(height: 1.35, fontSize: 13),
            ),
            if (info.director.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('Director · ${info.director}'),
              ),
            if (info.cast.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Cast · ${info.cast}'),
              ),
            const SizedBox(height: 24),
            if (series && seasons.isNotEmpty) ...[
              DropdownButtonFormField<int>(
                itemHeight: 48,
                style: Theme.of(context).textTheme.bodySmall,
                key: ValueKey(activeSeason),
                initialValue: activeSeason,
                decoration: const InputDecoration(
                  labelText: 'Season',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: seasons
                    .map(
                      (s) =>
                          DropdownMenuItem(value: s, child: Text('Season $s')),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    season = value;
                    episode = episodes
                        .where((e) => e.season == value)
                        .firstOrNull;
                  });
                  progressChanged();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Episode>(
                itemHeight: 48,
                style: Theme.of(context).textTheme.bodySmall,
                key: ValueKey('episode-${selected?.id}'),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Episode',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: visibleEpisodes
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          '${e.number}. ${e.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => episode = value);
                  progressChanged();
                },
              ),
              const SizedBox(height: 20),
            ],
            if (series && episodes.isEmpty)
              const Text('No episodes available.'),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: canResume ? 'Resume' : 'Play',
                  child: SizedBox(
                    width: canResume ? 330 : 110,
                    child: TextButton(
                      autofocus: true,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.transparent,
                        minimumSize: const Size(0, 44),
                        side: const BorderSide(color: Colors.white54),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: resolving || (series && selected == null)
                          ? null
                          : () => play(
                              info.item,
                              selected,
                              episodes,
                              artwork: info.artwork,
                            ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            resolving
                                ? 'Preparing...'
                                : canResume
                                ? 'Resume'
                                : 'Play',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (canResume) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: length.inMilliseconds > 0
                                    ? (played.inMilliseconds /
                                              length.inMilliseconds)
                                          .clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 3,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                                semanticsLabel: 'Playback progress',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '$remaining min left',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (canResume)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      side: const BorderSide(color: Colors.white54),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: resolving
                        ? null
                        : () => play(
                            info.item,
                            selected,
                            episodes,
                            artwork: info.artwork,
                            fromBeginning: true,
                          ),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text(
                      'Play from beginning',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MyListButton(
                      provider: widget.provider,
                      item: widget.item,
                      compact: series,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'My List',
                      style: series ? const TextStyle(fontSize: 13) : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: constraints.maxWidth < 700
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Artwork(info.artwork, width: 160, height: 230),
                      ),
                      const SizedBox(height: 24),
                      metadata,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(info.artwork, width: 190, height: 275),
                      const SizedBox(width: 32),
                      Expanded(child: metadata),
                    ],
                  ),
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
        final route = SmoothPageRoute<Episode>(
          builder: (_) => PlayerScreen(
            source: source,
            history: history,
            item: item,
            episode: current,
            nextEpisode: next,
            episodes: episodes,
            seriesArtwork: artwork,
            resumeAt: resumePosition,
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
