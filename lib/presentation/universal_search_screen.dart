import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/universal_search.dart';
import '../application/browsing_mode.dart';
import '../application/session.dart';
import '../application/watch_history.dart';
import '../data/recent_searches.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'activation_text_field.dart';
import 'profile_avatar.dart';
import 'lite_media_list.dart';
import 'media_horizontal_rail.dart';
import 'series_catalog_screen.dart';

class UniversalSearchScreen extends StatefulWidget {
  final IptvProvider provider;
  final Future<void> Function(ContentItem) onOpen;
  final Session? session;
  const UniversalSearchScreen({
    super.key,
    required this.provider,
    required this.onOpen,
    this.session,
  });
  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  late UniversalSearchController search;
  late RecentSearches history;
  List<String> recent = [];
  final text = TextEditingController();
  final input = FocusNode(debugLabel: 'Universal search');
  final field = GlobalKey<ActivationTextFieldState>();
  final filters = List.generate(4, (_) => FocusNode());
  final scroll = ScrollController();
  final rails = <int, GlobalKey<MediaHorizontalRailState>>{};
  final nodes = <int, FocusNode>{};
  final recentNodes = List.generate(9, (_) => FocusNode());
  final moreNodes = <int, FocusNode>{};
  bool editing = false;
  int historyVersion = 0;
  int get selected => search.filter == null
      ? 0
      : ContentType.values.indexOf(search.filter!) + 1;
  @override
  void initState() {
    super.initState();
    connect(widget.provider);
    widget.session?.addListener(sessionChanged);
    BrowsingModeSettings.instance.addListener(changed);
  }

  void connect(IptvProvider provider) {
    search = UniversalSearchController(provider)..addListener(changed);
    history = RecentSearches(WatchHistory.forProvider(provider).scope);
    final version = ++historyVersion;
    history.load().then((value) {
      if (mounted && version == historyVersion) setState(() => recent = value);
    });
    search.setQuery(text.text, immediate: true);
    search.reload();
  }

  @override
  void didUpdateWidget(covariant UniversalSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(sessionChanged);
      widget.session?.addListener(sessionChanged);
    }
    if (!identical(oldWidget.provider, widget.provider)) {
      search.removeListener(changed);
      search.dispose();
      recent = [];
      connect(widget.provider);
    }
  }

  void sessionChanged() {
    final provider = widget.session?.provider;
    if (provider == null || identical(provider, search.provider)) return;
    search.removeListener(changed);
    search.dispose();
    recent = [];
    connect(provider);
    changed();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> remember(String value) async {
    final repository = history;
    try {
      final rows = await repository.add(value);
      if (mounted && identical(repository, history)) {
        setState(() => recent = rows);
      }
    } catch (_) {
      /* Search remains usable if persistence is unavailable. */
    }
  }

  Future<void> open(ContentItem item) async {
    final focus = FocusManager.instance.primaryFocus;
    await remember(text.text);
    if (!mounted) return;
    await widget.onOpen(item);
    if (mounted && focus?.context != null) focus!.requestFocus();
  }

  void choose(ContentType? type) {
    search.setFilter(type);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  FocusNode moreNode(int index) => moreNodes.putIfAbsent(
    index,
    () => FocusNode(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          focusRow(index - 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          focusRow(index);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    ),
  );

  void focusRow(int index, {bool lite = false}) {
    if (index < 0) {
      filters[selected].requestFocus();
      return;
    }
    if (lite) {
      if (scroll.hasClients) {
        scroll.jumpTo((index * 76.0).clamp(0, scroll.position.maxScrollExtent));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) nodes[index]?.requestFocus();
      });
    } else {
      final key = rails[index];
      if (key?.currentState != null) {
        key!.currentState!.focusCurrent();
        return;
      }
      if (scroll.hasClients) {
        scroll.jumpTo(
          (index * 330.0).clamp(0, scroll.position.maxScrollExtent),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) rails[index]?.currentState?.focusCurrent();
      });
    }
  }

  List<({String title, List<ContentItem> items, ContentType? more})> groups() {
    if (search.query.isEmpty) {
      return search.recent.isEmpty
          ? []
          : [(title: 'Recently Added', items: search.recent, more: null)];
    }
    final result =
        <({String title, List<ContentItem> items, ContentType? more})>[];
    for (final type in UniversalSearchController.order) {
      if (search.filter != null && search.filter != type) continue;
      final items = search.results[type] ?? [];
      if (search.filter == null) {
        if (items.isNotEmpty) {
          result.add((
            title: type.label,
            items: items.take(10).toList(),
            more: items.length > 10 ? type : null,
          ));
        }
      } else {
        for (var i = 0; i < items.length; i += 10) {
          result.add((
            title: i == 0 ? '${type.label} (${items.length})' : '',
            items: items.skip(i).take(10).toList(),
            more: null,
          ));
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    widget.session?.removeListener(sessionChanged);
    BrowsingModeSettings.instance.removeListener(changed);
    search.removeListener(changed);
    search.dispose();
    text.dispose();
    input.dispose();
    scroll.dispose();
    for (final node in [
      ...filters,
      ...nodes.values,
      ...recentNodes,
      ...moreNodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lite = BrowsingModeSettings.instance.lite;
    final rows = groups();
    final flattened =
        <({String label, ContentItem? item, ContentType? more})>[];
    for (final group in rows) {
      flattened.add((label: group.title, item: null, more: group.more));
      flattened.addAll(
        group.items.map((item) => (label: item.name, item: item, more: null)),
      );
    }
    return PopScope(
      canPop: !editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          field.currentState?.finish();
          input.requestFocus();
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (editing) {
              field.currentState?.finish();
              input.requestFocus();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        },
        child: Scaffold(
          backgroundColor: const Color(0xff0d111b),
          appBar: AppBar(
            title: const Text('Search'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: !lite && widget.session?.activeProfile != null
                    ? ProfileAvatar(
                        widget.session!.activeProfile!.avatar,
                        size: 32,
                      )
                    : const Icon(Icons.person_outline),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ActivationTextField(
                        key: field,
                        controller: text,
                        focusNode: input,
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search channels, movies and series',
                        ),
                        onChanged: (value) {
                          search.setQuery(value);
                          setState(() {});
                        },
                        onSubmitted: (value) {
                          search.setQuery(value, immediate: true);
                          unawaited(remember(value));
                        },
                        onEditingChanged: (value) {
                          if (mounted) setState(() => editing = value);
                        },
                        onNavigateDown: () => filters[selected].requestFocus(),
                      ),
                    ),
                    if (text.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          text.clear();
                          search.setQuery('', immediate: true);
                          input.requestFocus();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Focus(
                          onKeyEvent: (_, event) {
                            if (event is! KeyDownEvent) {
                              return KeyEventResult.ignored;
                            }
                            final key = event.logicalKey;
                            if (key == LogicalKeyboardKey.arrowUp) {
                              input.requestFocus();
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowDown) {
                              if (search.query.isEmpty && recent.isNotEmpty) {
                                recentNodes.first.requestFocus();
                                return KeyEventResult.handled;
                              }
                              if (lite &&
                                  flattened.isNotEmpty &&
                                  flattened.first.item == null &&
                                  flattened.first.more == null) {
                                focusRow(1, lite: true);
                              } else {
                                focusRow(0, lite: lite);
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowLeft ||
                                key == LogicalKeyboardKey.arrowRight) {
                              filters[(i +
                                          (key == LogicalKeyboardKey.arrowLeft
                                              ? -1
                                              : 1))
                                      .clamp(0, 3)]
                                  .requestFocus();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: ChoiceChip(
                            selectedColor: const Color(0xff30445d),
                            side: WidgetStateBorderSide.resolveWith(
                              (states) => BorderSide(
                                color: states.contains(WidgetState.focused)
                                    ? const Color(0xff64b5f6)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            focusNode: filters[i],
                            label: Text(
                              i == 0 ? 'All' : ContentType.values[i - 1].label,
                            ),
                            selected: selected == i,
                            onSelected: (_) => choose(
                              i == 0 ? null : ContentType.values[i - 1],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (search.query.isEmpty && recent.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Focus(
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          filters[selected].requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          focusRow(lite ? 1 : 0, lite: lite);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: Wrap(
                        spacing: 8,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Recent searches'),
                          ),
                          for (final value in recent)
                            ActionChip(
                              focusNode: recentNodes[recent.indexOf(value)],
                              label: Text(value),
                              onPressed: () {
                                text.text = value;
                                search.setQuery(value, immediate: true);
                                unawaited(remember(value));
                              },
                            ),
                          ActionChip(
                            focusNode: recentNodes[8],
                            label: const Text('Clear history'),
                            onPressed: () async {
                              final repository = history;
                              await repository.clear();
                              if (mounted && identical(repository, history)) {
                                setState(() => recent = []);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (search.pending) const LinearProgressIndicator(minHeight: 2),
                if (search.errors.isNotEmpty)
                  TextButton(
                    onPressed: search.reload,
                    child: const Text('Some content could not load. Retry'),
                  ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            search.pending
                                ? 'Loading library...'
                                : search.query.isEmpty
                                ? 'Search your library'
                                : 'No results found',
                          ),
                        )
                      : lite
                      ? ListView.builder(
                          controller: scroll,
                          itemExtent: 76,
                          itemCount: flattened.length,
                          itemBuilder: (context, i) {
                            final row = flattened[i];
                            final node = nodes.putIfAbsent(
                              i,
                              () => FocusNode(),
                            );
                            return Focus(
                              onKeyEvent: (_, event) {
                                if (event is! KeyDownEvent) {
                                  return KeyEventResult.ignored;
                                }
                                final delta =
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowUp
                                    ? -1
                                    : event.logicalKey ==
                                          LogicalKeyboardKey.arrowDown
                                    ? 1
                                    : 0;
                                if (delta == 0) return KeyEventResult.ignored;
                                var next = i + delta;
                                while (next >= 0 &&
                                    next < flattened.length &&
                                    flattened[next].item == null &&
                                    flattened[next].more == null) {
                                  next += delta;
                                }
                                if (next < 0) {
                                  filters[selected].requestFocus();
                                } else if (next < flattened.length) {
                                  focusRow(next, lite: true);
                                }
                                return KeyEventResult.handled;
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: row.item == null
                                    ? row.more == null
                                          ? Align(
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                row.label,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                            )
                                          : TextButton(
                                              focusNode: node,
                                              onPressed: () => choose(row.more),
                                              child: Text(
                                                '${row.label} - View All',
                                              ),
                                            )
                                    : LiteMediaTile(
                                        focusNode: node,
                                        title: row.label,
                                        subtitle: row.item!.type.label,
                                        icon: row.item!.type == ContentType.live
                                            ? Icons.live_tv
                                            : Icons.movie_outlined,
                                        onOpen: () => open(row.item!),
                                      ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: rows.length,
                          itemExtent: 330,
                          itemBuilder: (context, i) {
                            final group = rows[i];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height: 44,
                                  child: Row(
                                    children: [
                                      Text(
                                        group.title,
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                      const Spacer(),
                                      if (group.more != null)
                                        TextButton(
                                          focusNode: moreNode(i),
                                          onPressed: () {
                                            choose(group.more);
                                            filters[selected].requestFocus();
                                          },
                                          child: const Text('View All'),
                                        ),
                                    ],
                                  ),
                                ),
                                MediaHorizontalRail(
                                  key: rails.putIfAbsent(
                                    i,
                                    () => GlobalKey<MediaHorizontalRailState>(),
                                  ),
                                  contentKey:
                                      '${search.query}:${search.filter}:$i',
                                  count: group.items.length,
                                  width: 170,
                                  height: 280,
                                  up: () {
                                    if (group.more != null) {
                                      moreNode(i).requestFocus();
                                    } else {
                                      focusRow(i - 1);
                                    }
                                  },
                                  down: () {
                                    if (i + 1 < rows.length) focusRow(i + 1);
                                  },
                                  itemBuilder: (j, node) {
                                    final item = group.items[j];
                                    return item.type == ContentType.live
                                        ? _LiveResult(
                                            key: ValueKey('live:${item.id}'),
                                            provider: search.provider,
                                            item: item,
                                            focusNode: node,
                                            onOpen: () => open(item),
                                          )
                                        : SeriesPosterCard(
                                            key: ValueKey(
                                              '${item.type.name}:${item.id}',
                                            ),
                                            item: item,
                                            provider: search.provider,
                                            focusNode: node,
                                            onOpen: () => open(item),
                                          );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveResult extends StatelessWidget {
  static final _epg = Expando<Map<String, Future<List<EpgProgramme>>>>();
  final IptvProvider provider;
  final ContentItem item;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  const _LiveResult({
    super.key,
    required this.item,
    required this.provider,
    required this.focusNode,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => TextButton(
    focusNode: focusNode,
    onPressed: onOpen,
    style: ButtonStyle(
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const Color(0xff30445d)
            : const Color(0xff1b2431),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? const Color(0xff64b5f6)
              : Colors.transparent,
          width: 2,
        ),
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (item.artwork != null)
          SharedArtworkImage(
            kind: ArtworkKind.poster,
            imageUrl: item.artwork.toString(),
            width: 56,
            height: 56,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) => const Icon(Icons.live_tv, size: 40),
          )
        else
          const Icon(Icons.live_tv, size: 40),
        const SizedBox(height: 12),
        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (provider is EpgProvider)
          FutureBuilder<List<EpgProgramme>>(
            future: (_epg[provider] ??= {}).putIfAbsent(
              item.id,
              () => (provider as EpgProvider).getEpg(item),
            ),
            builder: (context, snapshot) {
              final now = DateTime.now();
              final current = (snapshot.data ?? []).where(
                (p) => !now.isBefore(p.start) && now.isBefore(p.end),
              );
              return Text(
                current.isEmpty ? 'Live TV' : current.first.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            },
          )
        else
          const Text('Live TV'),
      ],
    ),
  );
}
