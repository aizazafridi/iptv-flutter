import 'widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../application/watch_history.dart';

class PlayerEpisodeDrawer extends StatefulWidget {
  final List<Episode> episodes;
  final Episode? current;
  final List<WatchEntry> history;
  final Uri? fallbackArtwork;
  const PlayerEpisodeDrawer({
    super.key,
    required this.episodes,
    this.current,
    this.fallbackArtwork,
    this.history = const [],
  });
  @override
  State<PlayerEpisodeDrawer> createState() => _PlayerEpisodeDrawerState();
}

class _PlayerEpisodeDrawerState extends State<PlayerEpisodeDrawer> {
  late int season = widget.current?.season ?? widget.episodes.first.season;
  final scroll = ScrollController();
  final seasonFocus = FocusNode();
  final seasonMenu = GlobalKey<PopupMenuButtonState<int>>();
  final nodes = <String, FocusNode>{};
  String? focused;
  List<Episode> get episodes =>
      widget.episodes.where((e) => e.season == season).toList()
        ..sort((a, b) => a.number.compareTo(b.number));
  @override
  void initState() {
    super.initState();
    seasonFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusEpisode(
        episodes
            .indexWhere((e) => e.id == widget.current?.id)
            .clamp(0, episodes.length - 1),
      ),
    );
  }

  void focusEpisode(int index) {
    if (!mounted) return;
    if (index < 0) {
      seasonFocus.requestFocus();
      return;
    }
    index = index.clamp(0, episodes.length - 1);
    final id = episodes[index].id;
    focused = id;
    if (scroll.hasClients) {
      scroll.jumpTo((index * 96.0).clamp(0, scroll.position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focused == id) nodes[id]?.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    scroll.dispose();
    seasonFocus.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = episodes;
    final seasons = widget.episodes.map((e) => e.season).toSet().toList()
      ..sort();
    return Column(
      children: [
        Focus(
          focusNode: seasonFocus,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.select)) {
              seasonMenu.currentState?.showButtonMenu();
              return KeyEventResult.handled;
            }
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              focusEpisode(0);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: PopupMenuButton<int>(
            key: seasonMenu,
            tooltip: 'Select season',
            onSelected: (value) {
              setState(() => season = value);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => focusEpisode(0),
              );
            },
            itemBuilder: (_) => [
              for (final value in seasons)
                PopupMenuItem(value: value, child: Text('Season $value')),
            ],
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: seasonFocus.hasFocus
                      ? const Color(0xff64b5f6)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('Season $season')),
                  const Icon(Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemExtent: 96,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final episode = rows[index];
              final saved = widget.history
                  .where((e) => e.episode?.id == episode.id)
                  .firstOrNull;
              final progress = saved == null || saved.duration.inSeconds <= 0
                  ? 0.0
                  : (saved.position.inSeconds / saved.duration.inSeconds).clamp(
                      0.0,
                      1.0,
                    );
              final node = nodes.putIfAbsent(episode.id, () => FocusNode());
              return Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent || event is KeyRepeatEvent) {
                    final at = rows.indexWhere((e) => e.id == focused);
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      focusEpisode(at - 1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      focusEpisode(at + 1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      seasonFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextButton(
                    focusNode: node,
                    onPressed: () => Navigator.pop(context, episode),
                    style: ButtonStyle(
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      foregroundColor: const WidgetStatePropertyAll(
                        Colors.white,
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (s) => episode.id == widget.current?.id
                            ? const Color(0xff30465d)
                            : const Color(0xff252e3a),
                      ),
                      side: WidgetStateProperty.resolveWith(
                        (s) => BorderSide(
                          color: s.contains(WidgetState.focused)
                              ? const Color(0xff64b5f6)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          height: 48,
                          child: Artwork(
                            episode.artwork ?? widget.fallbackArtwork,
                            width: 80,
                            height: 48,
                            fallbackUri: widget.fallbackArtwork,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'E${episode.number} \u00b7 ${episode.title}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                [
                                  episode.duration,
                                  if (progress > .95)
                                    'Watched'
                                  else if (saved != null)
                                    '${saved.position.inMinutes} min watched',
                                ].where((s) => s.isNotEmpty).join(' \u00b7 '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xffb4becc),
                                ),
                              ),
                              if (progress > 0)
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 3,
                                ),
                            ],
                          ),
                        ),
                        if (episode.id == widget.current?.id)
                          const Icon(Icons.play_arrow),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
