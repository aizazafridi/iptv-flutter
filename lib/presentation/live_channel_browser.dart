import '../application/live_favourite_groups.dart';
import 'live_favourite_dialogs.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../application/category_locks.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'activation_text_field.dart';
import 'lock_password_dialog.dart';
import 'widgets.dart';

/// Retained by the player while individual browser overlays are recreated.
class LiveChannelBrowserSelection {
  String? categoryId, groupId;
  final channelIds = <String, String>{};
}

/// Browsing owns only UI state: the existing player keeps its engine and surface.
class LiveChannelBrowser extends StatefulWidget {
  final bool embedded;
  final Future<List<ContentItem>> Function() load;
  final IptvProvider? provider;
  final String? currentId, categoryId;
  final LiveChannelBrowserSelection? selection;
  final Future<bool> Function(ContentItem)? onSelect;
  const LiveChannelBrowser({
    super.key,
    this.embedded = false,
    required this.load,
    this.provider,
    this.currentId,
    this.categoryId,
    this.selection,
    this.onSelect,
  });
  @override
  State<LiveChannelBrowser> createState() => _LiveChannelBrowserState();
}

class _LiveChannelBrowserState extends State<LiveChannelBrowser> {
  static const rowHeight = 86.0;
  final scroll = ScrollController();
  final selectorFocus = FocusNode(debugLabel: 'channel category selector');
  late final remembered = widget.selection ?? LiveChannelBrowserSelection();
  String get selectionKey => selectedCategory == 'favorites'
      ? 'group:${groups!.selectedGroup}'
      : 'category:$selectedCategory';
  final myListFocus = FocusNode(debugLabel: 'channel My List');
  final allModeFocus = FocusNode(debugLabel: 'channel All Channels');
  final searchFocus = FocusNode(debugLabel: 'channel search');
  final categorySearchInput = FocusNode(debugLabel: 'category search input');
  final channelSearchInput = FocusNode(debugLabel: 'channel search input');
  String lastProviderCategory = 'all', channelQuery = '';
  bool searchingChannels = false;
  final nodes = <String, FocusNode>{};

  final guides = <String, Future<List<EpgProgramme>>>{};
  List<Category> categories = [];
  List<ContentItem> rows = [];
  late Future<void> request;
  String selectedCategory = 'all', query = '';
  String? focusedId, error;
  String? selectedHere;
  late String? playingId = widget.currentId;
  bool choosingCategory = false, searching = false, busy = false;
  LiveFavouriteGroups? get groups => widget.provider == null
      ? null
      : LiveFavouriteGroups.forProvider(widget.provider!);
  Timer? clock;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    groups?.addListener(favoritesChanged);
    if (widget.provider != null) {
      MyList.forProvider(widget.provider!).addListener(favoritesChanged);
    }
    request = initialize();
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> initialize() async {
    try {
      final provider = widget.provider;
      if (provider != null) {
        final locks = CategoryLocks.forProvider(provider);
        await locks.load();
        final result = await provider.getCategories(ContentType.live);
        categories = result.where((c) => !locks.hidden(c)).toList();
      }
    } catch (_) {
      /* Channels remain usable if categories are unavailable. */
    }
    if (!mounted) return;
    final retained = widget.selection?.categoryId;
    if (retained == 'favorites' && widget.provider != null) {
      selectedCategory = 'favorites';
    } else if (retained == 'all' || categories.any((c) => c.id == retained)) {
      selectedCategory = retained!;
    } else if (categories.any((c) => c.id == widget.categoryId)) {
      selectedCategory = widget.categoryId!;
    }
    await loadCategory(selectedCategory, initial: true);
  }

  void favoritesChanged() {
    if (!mounted) return;
    if (selectedCategory == 'favorites') {
      MyList.forProvider(widget.provider!).items(ContentType.live).then((
        items,
      ) {
        if (mounted) {
          setState(
            () => rows = items
                .where(
                  (item) =>
                      !CategoryLocks.forProvider(
                        widget.provider!,
                      ).titleHidden(item) &&
                      (item.categoryId == null ||
                          !CategoryLocks.forProvider(widget.provider!).hidden(
                            Category(item.categoryId!, '', ContentType.live),
                          )),
                )
                .toList(),
          );
        }
      });
    }
    setState(() {});
  }

  List<ContentItem> get visible =>
      (selectedCategory == 'favorites'
              ? groups!.channels(groups!.selectedGroup, rows)
              : rows)
          .where(
            (item) => item.name.toLowerCase().contains(
              channelQuery.trim().toLowerCase(),
            ),
          )
          .toList();
  List<Category> get tabs =>
      [const Category('all', 'All', ContentType.live), ...categories]
          .where(
            (category) => category.name.toLowerCase().contains(
              query.trim().toLowerCase(),
            ),
          )
          .toList();

  Future<void> loadCategory(String id, {bool initial = false}) async {
    final version = ++revision;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final provider = widget.provider;
      if (provider != null && id != 'all' && id != 'favorites') {
        final category = categories.firstWhere((c) => c.id == id);
        final locks = CategoryLocks.forProvider(provider);
        if (locks.isLocked(category)) {
          final pin = await showDialog<String>(
            context: context,
            builder: (_) => LockPasswordDialog(locks: locks),
          );
          if (!mounted || version != revision) return;
          if (pin == null || !locks.unlock(category, pin)) {
            setState(() => busy = false);
            return;
          }
        }
      }
      List<ContentItem> result;
      if (provider == null) {
        result = await widget.load();
      } else if (id == 'favorites') {
        await groups!.load();
        if (initial && widget.selection?.groupId != null) {
          final saved = widget.selection!.groupId!;
          groups!.selectedGroup = groups!.exists(saved)
              ? saved
              : LiveFavouriteGroups.all;
        }
        result = await MyList.forProvider(provider).items(ContentType.live);
      } else if (id == 'all') {
        result = await widget.load();
      } else {
        result = await provider.getItems(
          categories.firstWhere((c) => c.id == id),
        );
      }
      if (provider != null) {
        final locks = CategoryLocks.forProvider(provider);
        result = result
            .where(
              (c) =>
                  !locks.titleHidden(c) &&
                  (c.categoryId == null ||
                      !locks.hidden(
                        Category(c.categoryId!, '', ContentType.live),
                      )),
            )
            .toList();
      }
      if (!mounted || version != revision) return;
      setState(() {
        rows = result;
        selectedCategory = id;
        if (id != 'favorites') lastProviderCategory = id;
        channelQuery = '';
        searchingChannels = false;
        widget.selection?.categoryId = id;
        if (id == 'favorites') {
          widget.selection?.groupId = groups!.selectedGroup;
        }
        choosingCategory = false;
        busy = false;
        query = '';
        searching = false;
      });
      final index = visible.indexWhere(
        (c) =>
            c.id ==
            (remembered.channelIds[selectionKey] ??
                (initial ? widget.currentId : null)),
      );
      focusChannel(index < 0 ? 0 : index);
      if (visible.isEmpty) selectorFocus.requestFocus();
    } catch (_) {
      if (mounted && version == revision) {
        setState(() {
          busy = false;
          error = 'Could not load channels. Please retry.';
        });
      }
    }
  }

  // Fixed row heights allow restoring channels far beyond the lazy viewport.
  void focusChannel(int index) {
    final items = visible;
    if (items.isEmpty) return;
    index = index.clamp(0, items.length - 1);
    final id = items[index].id;
    focusedId = id;
    remembered.channelIds[selectionKey] = id;
    final target = index * rowHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || choosingCategory) return;
      if (scroll.hasClients) {
        final position = scroll.position;
        if (target < position.pixels ||
            target + rowHeight > position.pixels + position.viewportDimension) {
          scroll.jumpTo(target.clamp(0, position.maxScrollExtent));
        }
      }
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && !choosingCategory && focusedId == id) {
        nodes[id]?.requestFocus();
      }
    });
  }

  void focusActiveCategory() => selectorFocus.requestFocus();
  void focusCategories() => selectorFocus.requestFocus();
  void focusGroups() => selectorFocus.requestFocus();

  final categoryCounts = <String, int>{};
  Future<void>? countsRequest;

  Future<void> loadCounts() async {
    try {
      final all =
          await (widget.provider?.getAllItems(ContentType.live) ??
              widget.load());
      if (!mounted) return;
      final locks = widget.provider == null
          ? null
          : CategoryLocks.forProvider(widget.provider!);
      final counts = <String, int>{
        'all': 0,
        for (final c in categories) c.id: 0,
      };
      for (final item in all) {
        if (locks != null &&
            (locks.titleHidden(item) ||
                (item.categoryId != null &&
                    locks.hidden(
                      Category(item.categoryId!, '', ContentType.live),
                    )))) {
          continue;
        }
        counts['all'] = counts['all']! + 1;
        if (item.categoryId != null) {
          counts.update(item.categoryId!, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      setState(() => categoryCounts.addAll(counts));
    } catch (_) {
      countsRequest = null;
    }
  }

  void openCategories() {
    if (busy || choosingCategory) return;
    setState(() => choosingCategory = true);
    if (selectedCategory != 'favorites') countsRequest ??= loadCounts();
  }

  void closeCategories() {
    returnToChannels();
    if (visible.isEmpty) selectorFocus.requestFocus();
  }

  Widget categoryView() => _ChannelCategoryList(
    options: selectedCategory == 'favorites'
        ? [for (final id in groupIds) (id, groups!.name(id))]
        : [
            ('all', 'All Categories'),
            for (final c in categories) (c.id, c.name),
          ],
    counts: selectedCategory == 'favorites'
        ? {for (final id in groupIds) id: groups!.channels(id, rows).length}
        : categoryCounts,
    selected: selectedCategory == 'favorites'
        ? groups!.selectedGroup
        : selectedCategory,
    title: selectedCategory == 'favorites' ? 'My List groups' : 'Categories',
    onBack: closeCategories,
    onSelect: (id) {
      if (selectedCategory == 'favorites') {
        setState(() => choosingCategory = false);
        selectGroup(id);
      } else {
        unawaited(loadCategory(id));
      }
    },
  );

  Widget categorySelector() => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        returnToChannels();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        (selectedCategory == 'favorites' ? myListFocus : allModeFocus)
            .requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        key: const ValueKey('live-category-selector'),
        focusNode: selectorFocus,
        onPressed: busy ? null : openCategories,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selectedCategory == 'favorites'
                    ? groups!.name(groups!.selectedGroup)
                    : categories
                              .where((c) => c.id == selectedCategory)
                              .firstOrNull
                              ?.name ??
                          'All Channels',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    ),
  );

  void returnToChannels() {
    setState(() => choosingCategory = false);
    final index = visible.indexWhere((c) => c.id == focusedId);
    focusChannel(index < 0 ? 0 : index);
  }

  Future<void> select(ContentItem item) async {
    if (busy) return;
    if (selectedHere == item.id && playingId == item.id) {
      Navigator.pop(context, item);
      return;
    }
    setState(() => busy = true);
    try {
      final success = widget.onSelect == null || await widget.onSelect!(item);
      if (!mounted) return;
      if (success) {
        setState(() {
          playingId = item.id;
          selectedHere = item.id;
          busy = false;
        });
      } else {
        setState(() => busy = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not play this channel. Please retry.';
        });
      }
    }
  }

  Future<void> actions(ContentItem item) async {
    if (widget.provider == null || busy) return;
    final previous = visible.indexWhere((c) => c.id == item.id);
    final saved = MyList.forProvider(widget.provider!).contains(item);
    final edit = await showDialog<bool>(
      context: context,
      builder: (context) => liveGroupsTheme(
        context,
        SimpleDialog(
          title: Text(item.name, style: const TextStyle(fontSize: 18)),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, true),
              child: Text(saved ? 'Manage My List' : 'Add to My List'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (edit == true && mounted) {
      await showLiveFavouriteDialog(context, widget.provider!, item);
    }
    if (mounted) {
      final index = visible.indexWhere((c) => c.id == item.id);
      focusChannel(
        index < 0
            ? previous.clamp(0, visible.isNotEmpty ? visible.length - 1 : 0)
            : index,
      );
    }
  }

  final epgLanes = <Future<void>>[Future.value(), Future.value()];
  int nextEpgLane = 0;
  Future<List<EpgProgramme>> guide(ContentItem item) =>
      guides.putIfAbsent(item.id, () {
        final lane = nextEpgLane++ % epgLanes.length;
        final requestedRevision = revision;
        final requestedGroup = groups?.selectedGroup;
        final request = epgLanes[lane].then((_) async {
          if (!mounted ||
              revision != requestedRevision ||
              groups?.selectedGroup != requestedGroup) {
            guides.remove(item.id);
            return <EpgProgramme>[];
          }
          try {
            final provider = widget.provider;
            return provider is EpgProvider
                ? await (provider as EpgProvider).getEpg(item)
                : <EpgProgramme>[];
          } catch (_) {
            return <EpgProgramme>[];
          }
        });
        epgLanes[lane] = request.then<void>((_) {});
        return request;
      });

  @override
  void dispose() {
    groups?.removeListener(favoritesChanged);
    if (widget.provider != null) {
      MyList.forProvider(widget.provider!).removeListener(favoritesChanged);
    }
    clock?.cancel();
    scroll.dispose();
    selectorFocus.dispose();
    for (final node in [
      myListFocus,
      allModeFocus,
      searchFocus,
      categorySearchInput,
      channelSearchInput,
      ...nodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> newGroup() async {
    final id = await showLiveGroupName(context, groups!);
    if (mounted && id != null) {
      setState(() {
        groups!.selectedGroup = id;
        widget.selection?.groupId = id;
      });
      focusGroups();
    }
  }

  List<String> get groupIds => [
    LiveFavouriteGroups.all,
    ...groups!.groups.map((g) => g.id),
  ];

  void selectGroup(String id) {
    setState(() {
      groups!.selectedGroup = id;
      widget.selection?.groupId = id;
      channelQuery = '';
      searchingChannels = false;
    });
    final index = visible.indexWhere(
      (c) => c.id == remembered.channelIds[selectionKey],
    );
    focusChannel(index < 0 ? 0 : index);
    if (visible.isEmpty) selectorFocus.requestFocus();
  }

  void openSearch({required bool channels}) {
    setState(() {
      searchingChannels = channels;
      searching = !channels;
      channelQuery = '';
      query = '';

      if (scroll.hasClients) scroll.jumpTo(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (channels ? channelSearchInput : categorySearchInput).requestFocus();
    });
  }

  Future<void> option(String value) async {
    if (value == 'channel') {
      final item =
          visible.where((c) => c.id == focusedId).firstOrNull ??
          visible.where((c) => c.id == playingId).firstOrNull ??
          visible.firstOrNull;
      if (item != null) await actions(item);
    } else if (value == 'search') {
      openSearch(channels: true);
    } else if (value == 'manage') {
      await showLiveGroupManager(context, widget.provider!);
      if (mounted) focusGroups();
    } else if (value == 'create') {
      await newGroup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = visible;
    final panel = Container(
      key: const ValueKey('live-channel-browser-panel'),
      width: widget.embedded
          ? double.infinity
          : MediaQuery.sizeOf(context).width * .36,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xf21b222d),
        borderRadius: BorderRadius.circular(16),
      ),
      child: choosingCategory
          ? categoryView()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Channels',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      focusNode: searchFocus,
                      tooltip: 'Search channels',
                      onPressed: () => openSearch(channels: true),
                      icon: const Icon(Icons.search, color: Colors.white70),
                    ),
                    if (widget.provider != null)
                      PopupMenuButton<String>(
                        tooltip: 'Channel options',
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                        ),
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'channel',
                            child: Text('Channel actions'),
                          ),
                          const PopupMenuItem(
                            value: 'search',
                            child: Text('Search channels'),
                          ),
                          if (selectedCategory == 'favorites') ...[
                            const PopupMenuItem(
                              value: 'manage',
                              child: Text('Manage Groups'),
                            ),
                            const PopupMenuItem(
                              value: 'create',
                              child: Text('Create New Group'),
                            ),
                          ],
                        ],
                        onSelected: option,
                      ),
                  ],
                ),
                if (searchingChannels)
                  ActivationTextField(
                    key: const ValueKey('live-channel-search-input'),
                    autofocus: true,
                    focusNode: channelSearchInput,
                    onNavigateUp: searchFocus.requestFocus,
                    onNavigateDown: () => allModeFocus.requestFocus(),
                    onSubmitted: (_) => returnToChannels(),
                    decoration: const InputDecoration(
                      hintText: 'Search channels',
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() {
                      channelQuery = value;
                      if (scroll.hasClients) scroll.jumpTo(0);
                    }),
                  ),
                if (searching)
                  ActivationTextField(
                    key: const ValueKey('live-category-search-input'),
                    autofocus: true,
                    focusNode: categorySearchInput,
                    onNavigateUp: searchFocus.requestFocus,
                    onNavigateDown: focusCategories,
                    onSubmitted: (_) => focusCategories(),
                    decoration: const InputDecoration(
                      hintText: 'Search categories',
                      isDense: true,
                    ),
                    onChanged: (value) => setState(() {
                      query = value;
                    }),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (selectedCategory == 'favorites') {
                          focusGroups();
                        } else {
                          focusCategories();
                        }
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        if (searchingChannels) {
                          channelSearchInput.requestFocus();
                        } else if (searching) {
                          categorySearchInput.requestFocus();
                        } else {
                          searchFocus.requestFocus();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: TextButton(
                            focusNode: allModeFocus,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              textStyle: const TextStyle(fontSize: 14),
                              foregroundColor: Colors.white,
                              backgroundColor: selectedCategory != 'favorites'
                                  ? const Color(0xff30445d)
                                  : const Color(0xff252f3d),
                            ),
                            onPressed: busy
                                ? null
                                : () => loadCategory(lastProviderCategory),
                            child: const Text(
                              'All Channels',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (widget.provider != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: TextButton(
                              focusNode: myListFocus,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                textStyle: const TextStyle(fontSize: 14),
                                foregroundColor: Colors.white,
                                backgroundColor: selectedCategory == 'favorites'
                                    ? const Color(0xff30445d)
                                    : const Color(0xff252f3d),
                              ),
                              onPressed: busy
                                  ? null
                                  : () => loadCategory('favorites'),
                              child: const Text(
                                'My List',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                categorySelector(),
                const Divider(color: Colors.white24, height: 18),
                if (busy) const LinearProgressIndicator(minHeight: 2),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(error!, style: const TextStyle(fontSize: 12)),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: busy
                              ? const CircularProgressIndicator()
                              : const Text('No channels available'),
                        )
                      : Scrollbar(
                          controller: scroll,
                          child: ListView.builder(
                            controller: scroll,
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              0,
                            ),
                            itemExtent: rowHeight,
                            itemCount: items.length,
                            itemBuilder: (_, index) {
                              final item = items[index];
                              return _ChannelRow(
                                key: ValueKey(item.id),
                                item: item,
                                number: rows.indexOf(item) + 1,
                                current: playingId == item.id,
                                node: nodes.putIfAbsent(
                                  item.id,
                                  () => FocusNode(),
                                ),
                                epg: guide(item),
                                onFocus: () {
                                  focusedId = item.id;
                                  remembered.channelIds[selectionKey] = item.id;
                                },
                                onUp: () => index == 0
                                    ? (selectedCategory == 'favorites'
                                          ? focusGroups()
                                          : focusCategories())
                                    : focusChannel(index - 1),
                                onDown: () => focusChannel(index + 1),
                                onLeft: focusActiveCategory,
                                onSelect: busy ? null : () => select(item),
                                onActions: () => actions(item),
                              );
                            },
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    choosingCategory
                        ? 'Up/Down browse, OK select, Back close'
                        : 'Up/Down browse, Left categories or groups, OK watch, Menu channel actions, Back close',
                    maxLines: 2,
                    style: const TextStyle(fontSize: 10, color: Colors.white60),
                  ),
                ),
              ],
            ),
    );
    final themed = RepaintBoundary(
      key: const ValueKey('live-channel-selector-paint'),
      child: PopScope(
        canPop: !choosingCategory,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && choosingCategory) closeCategories();
        },
        child: liveGroupsTheme(context, panel),
      ),
    );
    if (widget.embedded) return themed;
    return Dialog(
      alignment: Alignment.centerLeft,
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(12),
      child: themed,
    );
  }
}

class _ChannelCategoryList extends StatefulWidget {
  final List<(String, String)> options;
  final Map<String, int> counts;
  final String selected, title;
  final VoidCallback onBack;
  final ValueChanged<String> onSelect;
  const _ChannelCategoryList({
    required this.options,
    required this.counts,
    required this.selected,
    required this.title,
    required this.onBack,
    required this.onSelect,
  });
  @override
  State<_ChannelCategoryList> createState() => _ChannelCategoryListState();
}

class _ChannelCategoryListState extends State<_ChannelCategoryList> {
  final scroll = ScrollController();
  final nodes = <String, FocusNode>{};
  final search = FocusNode(debugLabel: 'category search control');
  final input = FocusNode(debugLabel: 'category search input');
  bool searching = false;
  String query = '';
  List<(String, String)> get options => widget.options
      .where((o) => o.$2.toLowerCase().contains(query.trim().toLowerCase()))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focus(options.indexWhere((o) => o.$1 == widget.selected)),
    );
  }

  void focus(int index) {
    if (!mounted) return;
    if (index < 0 || options.isEmpty) {
      (searching ? input : search).requestFocus();
      return;
    }
    index = index.clamp(0, options.length - 1);
    final id = options[index].$1;
    if (scroll.hasClients) {
      scroll.jumpTo((index * 56.0).clamp(0, scroll.position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) nodes[id]?.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    scroll.dispose();
    search.dispose();
    input.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          [
            LogicalKeyboardKey.escape,
            LogicalKeyboardKey.goBack,
          ].contains(event.logicalKey)) {
        widget.onBack();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Column(
      key: const ValueKey('live-category-list'),
      children: [
        Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (searching) {
                input.requestFocus();
              } else {
                focus(
                  options
                      .indexWhere((o) => o.$1 == widget.selected)
                      .clamp(0, options.length),
                );
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back to channels',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                focusNode: search,
                tooltip: 'Search categories',
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() {
                    searching = !searching;
                    query = '';
                  });
                  if (searching) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) input.requestFocus();
                    });
                  }
                },
              ),
            ],
          ),
        ),
        if (searching)
          ActivationTextField(
            key: const ValueKey('live-category-search-input'),
            focusNode: input,
            decoration: const InputDecoration(
              hintText: 'Search categories',
              isDense: true,
            ),
            onNavigateUp: search.requestFocus,
            onNavigateDown: () => focus(0),
            onSubmitted: (_) => focus(0),
            onChanged: (value) {
              setState(() => query = value);
              if (scroll.hasClients) scroll.jumpTo(0);
            },
          ),
        const Divider(color: Colors.white24, height: 18),
        Expanded(
          child: options.isEmpty
              ? const Center(child: Text('No matching categories'))
              : ListView.builder(
                  controller: scroll,
                  itemExtent: 56,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final node = nodes.putIfAbsent(
                      option.$1,
                      () =>
                          FocusNode(debugLabel: 'channel option ${option.$1}'),
                    );
                    return Focus(
                      canRequestFocus: false,
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                            event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          focus(
                            index +
                                (event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown
                                    ? 1
                                    : -1),
                          );
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: ListenableBuilder(
                        listenable: node,
                        builder: (_, _) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: TextButton(
                            focusNode: node,
                            onPressed: () => widget.onSelect(option.$1),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  node.hasFocus || option.$1 == widget.selected
                                  ? const Color(0xff354962)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: node.hasFocus
                                      ? const Color(0xff9acaff)
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option.$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.counts[option.$1]?.toString() ?? '?',
                                  style: const TextStyle(color: Colors.white60),
                                ),
                                const SizedBox(width: 8),
                                if (option.$1 == widget.selected)
                                  const Icon(
                                    Icons.check,
                                    size: 18,
                                    color: Color(0xff9acaff),
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
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'OK Select ? Back Channels',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ),
      ],
    ),
  );
}

class _ChannelRow extends StatefulWidget {
  final ContentItem item;
  final int number;
  final bool current;
  final FocusNode node;
  final Future<List<EpgProgramme>> epg;
  final VoidCallback onUp, onDown, onLeft, onFocus, onActions;
  final VoidCallback? onSelect;
  const _ChannelRow({
    super.key,
    required this.item,
    required this.number,
    required this.current,
    required this.node,
    required this.epg,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onFocus,
    required this.onActions,
    this.onSelect,
  });
  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  Timer? hold;
  bool focused = false, longPressed = false, pressed = false;
  KeyEventResult key(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.contextMenu ||
              event.logicalKey == LogicalKeyboardKey.f10)) {
        widget.onActions();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent && !pressed) {
        pressed = true;
        longPressed = false;
        hold = Timer(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          longPressed = true;
          widget.onActions();
        });
      } else if (event is KeyUpEvent && pressed) {
        hold?.cancel();
        pressed = false;
        if (!longPressed) widget.onSelect?.call();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (key == LogicalKeyboardKey.arrowUp) {
        widget.onUp();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        widget.onDown();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onLeft();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    onKeyEvent: key,
    onFocusChange: (value) {
      setState(() => focused = value);
      if (value) {
        widget.onFocus();
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 150),
        );
      } else {
        hold?.cancel();
        pressed = false;
      }
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: focused ? const Color(0xff354962) : const Color(0xff242c36),
        border: Border.all(
          color: focused ? const Color(0xff9acaff) : Colors.transparent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onSelect,
          onLongPress: widget.onActions,
          child: FutureBuilder<List<EpgProgramme>>(
            future: widget.epg,
            builder: (context, snapshot) {
              final now = DateTime.now();
              final programme = snapshot.data
                  ?.where((p) => p.isCurrent(now))
                  .firstOrNull;
              final duration =
                  programme?.end.difference(programme.start).inMilliseconds ??
                  0;
              final progress = programme == null || duration <= 0
                  ? 0.0
                  : (now.difference(programme.start).inMilliseconds / duration)
                        .clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '${widget.number}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox.square(
                            dimension: 40,
                            child: ChannelLogo(widget.item.artwork),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  programme?.title ??
                                      (snapshot.connectionState ==
                                              ConnectionState.waiting
                                          ? 'Loading guide?'
                                          : 'Programme information unavailable'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.current)
                            const Icon(
                              Icons.play_circle_outline,
                              color: Color(0xff9acaff),
                              size: 16,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      color: const Color(0xff64b5f6),
                      backgroundColor: Colors.white24,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
