import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'widgets.dart';

class EpisodePicker extends StatefulWidget {
  final List<Episode> episodes;
  final String? currentId;
  final Uri? fallbackArtwork;
  const EpisodePicker({
    super.key,
    required this.episodes,
    this.currentId,
    this.fallbackArtwork,
  });
  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  late final scroll = ScrollController(
    initialScrollOffset:
        widget.episodes
            .indexWhere((episode) => episode.id == widget.currentId)
            .clamp(0, widget.episodes.length) *
        217.0,
  );
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void move(int direction) {
    if (!scroll.hasClients) return;
    scroll.animateTo(
      (scroll.offset + direction * 434).clamp(
        0,
        scroll.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    alignment: Alignment.centerRight,
    insetPadding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 300,
        maxHeight: MediaQuery.sizeOf(context).height - 24,
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Episodes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous episodes',
                  onPressed: () => move(-1),
                  icon: const Icon(
                    Icons.keyboard_arrow_up,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'More episodes',
                  onPressed: () => move(1),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: 'Close episodes',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
            Flexible(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height - 100,
                child: ListView.separated(
                  controller: scroll,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.episodes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final episode = widget.episodes[index];
                    final selected = episode.id == widget.currentId;
                    return SizedBox(
                      height: 205,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(context, episode),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? Colors.white : Colors.white24,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Artwork(
                                      episode.artwork ?? widget.fallbackArtwork,
                                      fallbackUri: widget.fallbackArtwork,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'S${episode.season} · E${episode.number} · ${episode.title}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (selected)
                                  const Text(
                                    'Now playing',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
