import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import '../application/category_locks.dart';
import '../data/last_live_channel.dart';
import '../data/locked_provider.dart';

class OnNowPanel extends StatefulWidget {
  final bool embedded;
  final FocusNode? entryFocusNode;
  final IptvProvider provider;
  final Future<void> Function(ContentItem) onOpen;
  const OnNowPanel({
    super.key,
    required this.provider,
    required this.onOpen,
    this.embedded = false,
    this.entryFocusNode,
  });
  @override
  State<OnNowPanel> createState() => _OnNowPanelState();
}

class _OnNowPanelState extends State<OnNowPanel> {
  late final recent = LastLiveChannel.forProvider(widget.provider);
  late Future<List<ContentItem>> channels = load();
  late final locks = CategoryLocks.forProvider(widget.provider);
  final guides = <String, Future<List<EpgProgramme>>>{};
  Timer? timer;
  @override
  void initState() {
    super.initState();
    recent.changes.addListener(refresh);
    locks.addListener(refresh);
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  void refresh() {
    if (mounted) {
      setState(() {
        guides.clear();
        channels = load();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    recent.changes.removeListener(refresh);
    locks.removeListener(refresh);
    super.dispose();
  }

  Future<List<ContentItem>> load() async {
    final rows = await recent.recentChannels();
    await locks.load();
    final p = widget.provider;
    final visible = p is LockedProvider
        ? await p.visibleSavedItems(rows, excludeConfiguredLocks: true)
        : await locks.visibleItems(rows, excludeConfiguredLocks: true);
    return visible.take(5).toList();
  }

  Future<List<EpgProgramme>> guide(ContentItem item) =>
      guides.putIfAbsent(item.id, () async {
        final p = widget.provider;
        return p is EpgProvider
            ? (p as EpgProvider).getEpg(item)
            : <EpgProgramme>[];
      });
  @override
  Widget build(BuildContext context) => Material(
    color: widget.embedded ? Colors.transparent : const Color(0xff191d24),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'On now',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<ContentItem>>(
              future: channels,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      focusNode: widget.entryFocusNode,
                      onPressed: refresh,
                      child: const Text('Retry channels'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return Focus(
                    focusNode: widget.entryFocusNode,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return Focus(
                    focusNode: widget.entryFocusNode,
                    child: const Center(
                      child: Text(
                        'Watch a channel to see what is on now.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final item in rows)
                      Expanded(
                        child: ListTile(
                          minTileHeight: 0,
                          minVerticalPadding: 0,
                          focusNode: item.id == rows.first.id
                              ? widget.entryFocusNode
                              : null,
                          focusColor: const Color(0xff284f77),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FutureBuilder<List<EpgProgramme>>(
                                  future: guide(item),
                                  builder: (context, snapshot) {
                                    final current = snapshot.data
                                        ?.where(
                                          (p) => p.isCurrent(DateTime.now()),
                                        )
                                        .firstOrNull;
                                    return Text(
                                      current?.title ??
                                          (snapshot.connectionState !=
                                                  ConnectionState.done
                                              ? 'Loading...'
                                              : 'Guide unavailable'),
                                      maxLines: 1,
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white54,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          onTap: () => widget.onOpen(item),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
