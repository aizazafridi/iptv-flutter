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
    appBar: AppBar(
      title: Text(widget.item.name),
      actions: [MyListButton(provider: widget.provider, item: widget.item)],
    ),
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
        final metadata = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.item.name,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
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
              style: const TextStyle(height: 1.6),
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
                key: ValueKey(activeSeason),
                initialValue: activeSeason,
                decoration: const InputDecoration(labelText: 'Season'),
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
                key: ValueKey('episode-${selected?.id}'),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Episode'),
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
            FilledButton.icon(
              onPressed: resolving || (series && selected == null)
                  ? null
                  : () => play(
                      info.item,
                      selected,
                      episodes,
                      artwork: info.artwork,
                    ),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                resolving
                    ? 'Preparing…'
                    : previous != null &&
                          (!series || selected?.id == previous?.episode?.id)
                    ? 'Resume'
                    : 'Play',
              ),
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
                        child: Artwork(info.artwork, width: 200, height: 290),
                      ),
                      const SizedBox(height: 24),
                      metadata,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(info.artwork, width: 250, height: 365),
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
  }) async {
    setState(() => resolving = true);
    try {
      Episode? current = selected;
      while (mounted) {
        final saved = await history.latest(item, episode: current);
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
            resumeAt: saved?.position ?? Duration.zero,
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
