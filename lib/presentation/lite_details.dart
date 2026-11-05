import 'package:flutter/material.dart';
import '../application/watch_history.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'lite_media_list.dart';
import 'my_list_button.dart';

String liteDuration(String value) {
  final parts = value.split(':').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((p) => p == null)) return value;
  final hours = parts[0]!, minutes = parts[1]!;
  return [if (hours > 0) '${hours}h', if (minutes > 0) '${minutes}m'].join(' ');
}

class LiteDetails extends StatefulWidget {
  final IptvProvider provider;
  final MediaDetails info;
  final List<Episode> episodes;
  final WatchEntry? previous;
  final bool resolving;
  final Future<void> Function(Episode?, bool) onPlay;
  const LiteDetails({
    super.key,
    required this.provider,
    required this.info,
    required this.episodes,
    required this.previous,
    required this.resolving,
    required this.onPlay,
  });
  @override
  State<LiteDetails> createState() => _LiteDetailsState();
}

class _LiteDetailsState extends State<LiteDetails> {
  late final history = WatchHistory.forProvider(widget.provider);
  late Future<List<WatchEntry>> progress = history.seriesProgress(
    widget.info.item,
  );
  final seasonsFocus = FocusNode(debugLabel: 'lite seasons');
  int? selectedSeason;
  bool get series => widget.info.item.type == ContentType.series;
  @override
  void initState() {
    super.initState();
    history.addListener(refresh);
  }

  void refresh() {
    if (mounted) {
      setState(() => progress = history.seriesProgress(widget.info.item));
    }
  }

  @override
  void dispose() {
    history.removeListener(refresh);
    seasonsFocus.dispose();
    super.dispose();
  }

  String remaining(WatchEntry entry) =>
      '${((entry.duration - entry.position).inSeconds / 60).ceil().clamp(0, 99999)} min left';
  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final seasons = widget.episodes.map((e) => e.season).toSet().toList()
      ..sort();
    final season =
        selectedSeason ??
        widget.previous?.episode?.season ??
        seasons.firstOrNull;
    final current = widget.episodes.where((e) => e.season == season).toList();
    final target =
        widget.episodes
            .where((e) => e.id == widget.previous?.episode?.id)
            .firstOrNull ??
        widget.episodes.firstOrNull;
    final previous = widget.previous;
    final resumable =
        previous != null &&
        previous.position > Duration.zero &&
        previous.duration > previous.position;
    final metadata = [
      if (info.releaseDate.isNotEmpty) info.releaseDate.split('-').first,
      info.genre,
      liteDuration(info.duration),
      if (info.rating.isNotEmpty) 'Rating: ${info.rating}',
    ].where((v) => v.isNotEmpty).join(' \u00b7 ');
    final actions = Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        FilledButton.icon(
          autofocus: true,
          onPressed: widget.resolving || (series && target == null)
              ? null
              : () => widget.onPlay(target, false),
          icon: const Icon(Icons.play_arrow),
          label: Text(
            resumable
                ? 'Resume${series && target != null ? ' S${target.season} E${target.number}' : ''} \u00b7 ${remaining(previous)}'
                : series
                ? target == null
                      ? 'No episodes available'
                      : 'Play S${target.season} E${target.number}'
                : 'Play Movie',
          ),
        ),
        if (resumable)
          OutlinedButton(
            onPressed: widget.resolving
                ? null
                : () => widget.onPlay(target, true),
            child: const Text('Play From Beginning'),
          ),
        MyListButton(
          provider: widget.provider,
          item: info.item,
          showLabel: true,
        ),
      ],
    );
    return ColoredBox(
      color: const Color(0xff0d121b),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  Expanded(
                    child: Text(
                      info.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 26,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (metadata.isNotEmpty)
                Text(
                  metadata,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xffaab8c9),
                  ),
                ),
              const SizedBox(height: 8),
              if (!series)
                Expanded(
                  child: ListView(
                    children: [
                      Text(info.synopsis, style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 12),
                      actions,
                      if (info.cast.isNotEmpty || info.director.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Cast & Crew',
                          style: TextStyle(fontSize: 18),
                        ),
                        if (info.director.isNotEmpty)
                          Text('Director: ${info.director}'),
                        if (info.cast.isNotEmpty) Text(info.cast),
                      ],
                    ],
                  ),
                )
              else ...[
                if (info.synopsis.isNotEmpty)
                  Text(
                    info.synopsis,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                const SizedBox(height: 8),
                actions,
                if (seasons.isNotEmpty)
                  DropdownButton<int>(
                    focusNode: seasonsFocus,
                    value: seasons.contains(season) ? season : seasons.first,
                    items: [
                      for (final number in seasons)
                        DropdownMenuItem(
                          value: number,
                          child: Text('Season $number'),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => selectedSeason = value),
                  ),
                Expanded(
                  child: FutureBuilder<List<WatchEntry>>(
                    future: progress,
                    builder: (context, snapshot) {
                      final saved = {
                        for (final entry in snapshot.data ?? <WatchEntry>[])
                          entry.episode?.id: entry,
                      };
                      if (current.isEmpty) {
                        return const Center(
                          child: Text('No episodes available.'),
                        );
                      }
                      return LiteMediaList(
                        key: ValueKey(season),
                        up: seasonsFocus.requestFocus,
                        items: [
                          for (final episode in current)
                            ContentItem(
                              id: episode.id,
                              name:
                                  'S${episode.season} E${episode.number} \u00b7 ${episode.title}',
                              type: ContentType.series,
                            ),
                        ],
                        subtitle: (item) {
                          final episode = current.firstWhere(
                                (e) => e.id == item.id,
                              ),
                              entry = saved[item.id];
                          final status = entry == null
                              ? 'Not Watched'
                              : entry.duration > Duration.zero &&
                                    entry.position.inMilliseconds >=
                                        entry.duration.inMilliseconds * .95
                              ? 'Watched'
                              : 'Continue Watching \u00b7 ${remaining(entry)}';
                          return [
                            liteDuration(episode.duration),
                            status,
                          ].where((v) => v.isNotEmpty).join(' \u00b7 ');
                        },
                        progress: (item) {
                          final entry = saved[item.id];
                          return entry == null ||
                                  entry.duration <= Duration.zero
                              ? null
                              : entry.position.inMilliseconds /
                                    entry.duration.inMilliseconds;
                        },
                        onOpen: (item) => widget.onPlay(
                          current.firstWhere((e) => e.id == item.id),
                          false,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
