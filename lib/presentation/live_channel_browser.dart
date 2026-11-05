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
  final categoryScroll = ScrollController();
  final groupScroll = ScrollController();
  final myListFocus = FocusNode(debugLabel: 'channel My List');
  final allModeFocus = FocusNode(debugLabel: 'channel All Channels');
  final searchFocus = FocusNode(debugLabel: 'channel search');
  final categorySearchInput = FocusNode(debugLabel: 'category search input');
  final channelSearchInput = FocusNode(debugLabel: 'channel search input');
  String lastProviderCategory = 'all', channelQuery = '';
  bool searchingChannels = false;
  final nodes = <String, FocusNode>{};
  final groupNodes = <String, FocusNode>{};
  final categoryNodes = <String, FocusNode>{};
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
        (c) => c.id == (initial ? widget.currentId : focusedId),
      );
      focusChannel(index < 0 ? 0 : index);
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

  List<Category>? measuredCategories;
  TextScaler? measuredScaler;
  TextDirection? measuredDirection;
  double? measuredCategoryWidth;
  double get categoryWidth {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    if (identical(measuredCategories, categories) &&
        measuredScaler == scaler &&
        measuredDirection == direction &&
        measuredCategoryWidth != null) {
      return measuredCategoryWidth!;
    }
    var width = 126.0;
    // Measure the provider labels once, not once per group on each focus change.
    // Search filters do not change the shared tab width or force new layouts.
    final painter = TextPainter(textDirection: direction, textScaler: scaler);
    for (final category in categories) {
      painter.text = TextSpan(
        text: category.name,
        style: const TextStyle(fontSize: 12),
      );
      painter.layout();
      if (painter.width + 38 > width) width = painter.width + 38;
    }
    painter.dispose();
    measuredCategories = categories;
    measuredScaler = scaler;
    measuredDirection = direction;
    return measuredCategoryWidth = width;
  }

  void focusActiveCategory() {
    if (selectedCategory == 'favorites') {
      focusGroups();
    } else {
      focusCategories();
    }
  }

  void focusCategories() {
    if (busy) return;
    setState(() {
      choosingCategory = true;
    });
    focusCategory(tabs.indexWhere((c) => c.id == selectedCategory));
  }

  void focusCategory(int index) {
    if (tabs.isEmpty) {
      searchFocus.requestFocus();
      return;
    }
    index = index.clamp(0, tabs.length - 1);
    final id = tabs[index].id;
    final target = index * categoryWidth;
    if (categoryScroll.hasClients) {
      categoryScroll.jumpTo(
        target.clamp(0, categoryScroll.position.maxScrollExtent),
      );
    }
    final node = categoryNodes[id];
    if (node?.context != null) {
      node!.requestFocus();
      return;
    }
    // A new category view or a lazy off-screen row needs one layout frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && choosingCategory) categoryNodes[id]?.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void focusGroups() {
    if (selectedCategory != 'favorites') {
      focusCategories();
      return;
    }
    final id = groups!.exists(groups!.selectedGroup)
        ? groups!.selectedGroup
        : LiveFavouriteGroups.all;
    if (busy) return;
    setState(() => choosingCategory = true);
    final index = groupIds.indexOf(id);
    focusGroupAt(index < 0 ? 0 : index);
  }

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
    categoryScroll.dispose();
    groupScroll.dispose();
    for (final node in [
      myListFocus,
      allModeFocus,
      searchFocus,
      categorySearchInput,
      channelSearchInput,
      ...nodes.values,
      ...categoryNodes.values,
      ...groupNodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Widget categoryStrip() => SizedBox(
    height: 42,
    child: ListView.builder(
      controller: categoryScroll,
      scrollDirection: Axis.horizontal,
      itemExtent: categoryWidth,
      itemCount: tabs.length,
      itemBuilder: (_, index) {
        final category = tabs[index];
        final node = categoryNodes.putIfAbsent(
          category.id,
          () => FocusNode(debugLabel: 'channel category ${category.id}'),
        );
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Focus(
            focusNode: node,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                focusCategory(index - 1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                focusCategory(index + 1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                if (searching) {
                  categorySearchInput.requestFocus();
                } else {
                  allModeFocus.requestFocus();
                }
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                returnToChannels();
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                if (!busy) unawaited(loadCategory(category.id));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: channelTab(
              category.name,
              node,
              selected: category.id == selectedCategory,
              onTap: () => loadCategory(category.id),
            ),
          ),
        );
      },
    ),
  );
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

  Widget channelTab(
    String label,
    FocusNode node, {
    required bool selected,
    required VoidCallback onTap,
  }) => ListenableBuilder(
    listenable: node,
    builder: (_, _) => Material(
      color: node.hasFocus
          ? const Color(0xff30445d)
          : selected
          ? const Color(0xff293546)
          : const Color(0xff252f3d),
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        canRequestFocus: false,
        onTap: busy
            ? null
            : () {
                node.requestFocus();
                onTap();
              },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: node.hasFocus
                  ? const Color(0xff64b5f6)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ),
      ),
    ),
  );

  List<String> get groupIds => [
    LiveFavouriteGroups.all,
    ...groups!.groups.map((g) => g.id),
  ];

  void focusGroupAt(int index) {
    final ids = groupIds;
    final targetIndex = index.clamp(0, ids.length - 1);
    final id = ids[targetIndex];
    if (groupScroll.hasClients) {
      final start = targetIndex * categoryWidth;
      final position = groupScroll.position;
      final end = start + categoryWidth;
      final target = start < position.pixels
          ? start
          : end > position.pixels + position.viewportDimension
          ? end - position.viewportDimension
          : position.pixels;
      if ((target - position.pixels).abs() > .5) {
        unawaited(
          groupScroll.animateTo(
            target.clamp(0, position.maxScrollExtent),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          ),
        );
      }
    }
    final node = groupNodes[id];
    if (node?.context != null) {
      node!.requestFocus();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && choosingCategory) groupNodes[id]?.requestFocus();
      });
    }
  }

  Widget groupStrip() => SizedBox(
    height: 42,
    child: SingleChildScrollView(
      controller: groupScroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final id in groupIds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: categoryWidth - 6,
                child: Focus(
                  focusNode: groupNodes.putIfAbsent(
                    id,
                    () => FocusNode(debugLabel: 'channel group $id'),
                  ),
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    final index = groupIds.indexOf(id);
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      focusGroupAt(index - 1);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      if (index + 1 < groupIds.length) {
                        focusGroupAt(index + 1);
                      } else {
                        node.nextFocus();
                      }
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      returnToChannels();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      myListFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.select)) {
                      if (!busy) selectGroup(id);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: channelTab(
                    groups!.name(id),
                    groupNodes[id]!,
                    selected:
                        (groups!.exists(groups!.selectedGroup)
                            ? groups!.selectedGroup
                            : LiveFavouriteGroups.all) ==
                        id,
                    onTap: () => selectGroup(id),
                  ),
                ),
              ),
            ),
          TextButton(onPressed: newGroup, child: const Text('+ New Group')),
          TextButton(
            onPressed: () async {
              await showLiveGroupManager(context, widget.provider!);
              if (mounted) focusGroups();
            },
            child: const Text('Manage Groups'),
          ),
        ],
      ),
    ),
  );

  void selectGroup(String id) => setState(() {
    groups!.selectedGroup = id;
    widget.selection?.groupId = id;
    if (scroll.hasClients) scroll.jumpTo(0);
  });

  void openSearch({required bool channels}) {
    setState(() {
      searchingChannels = channels;
      searching = !channels;
      channelQuery = '';
      query = '';
      if (categoryScroll.hasClients) categoryScroll.jumpTo(0);
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
          : MediaQuery.sizeOf(context).width * .45,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xf21b222d),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
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
              if (selectedCategory != 'favorites')
                TextButton.icon(
                  onPressed: busy ? null : focusCategories,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text(
                    'Categories',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              IconButton(
                focusNode: searchFocus,
                tooltip: selectedCategory == 'favorites'
                    ? 'Search channels'
                    : 'Search categories',
                onPressed: () =>
                    openSearch(channels: selectedCategory == 'favorites'),
                icon: const Icon(Icons.search, color: Colors.white70),
              ),
              IconButton(
                tooltip: 'Search channels',
                icon: const Icon(Icons.manage_search),
                onPressed: () => openSearch(channels: true),
              ),
              if (widget.provider != null)
                PopupMenuButton<String>(
                  tooltip: 'Channel options',
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
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
          if (searching && selectedCategory != 'favorites')
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
                if (categoryScroll.hasClients) categoryScroll.jumpTo(0);
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
                  TextButton.icon(
                    focusNode: allModeFocus,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: selectedCategory != 'favorites'
                          ? const Color(0xff30445d)
                          : const Color(0xff252f3d),
                    ),
                    onPressed: busy
                        ? null
                        : () => loadCategory(lastProviderCategory),
                    icon: const Icon(Icons.list, size: 18),
                    label: const Text('All Channels'),
                  ),
                  if (widget.provider != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      focusNode: myListFocus,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: selectedCategory == 'favorites'
                            ? const Color(0xff30445d)
                            : const Color(0xff252f3d),
                      ),
                      onPressed: busy ? null : () => loadCategory('favorites'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('My List'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (selectedCategory == 'favorites')
            groupStrip()
          else
            categoryStrip(),
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
                      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                      itemExtent: rowHeight,
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return _ChannelRow(
                          key: ValueKey(item.id),
                          item: item,
                          number: rows.indexOf(item) + 1,
                          current: playingId == item.id,
                          node: nodes.putIfAbsent(item.id, () => FocusNode()),
                          epg: guide(item),
                          onFocus: () => focusedId = item.id,
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
                  ? 'Left/Right browse, OK select, Down channels'
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
      child: liveGroupsTheme(context, panel),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
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
                      Row(
                        children: [
                          Text(
                            '${widget.number} ',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              widget.item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
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
                      const SizedBox(height: 4),
                      FutureBuilder<List<EpgProgramme>>(
                        future: widget.epg,
                        builder: (context, snapshot) {
                          final now = DateTime.now();
                          final current = snapshot.data
                              ?.where((p) => p.isCurrent(now))
                              .firstOrNull;
                          final duration =
                              current?.end
                                  .difference(current.start)
                                  .inMilliseconds ??
                              0;
                          final progress = current == null || duration <= 0
                              ? 0.0
                              : (now.difference(current.start).inMilliseconds /
                                        duration)
                                    .clamp(0.0, 1.0);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current?.title ??
                                    (snapshot.connectionState ==
                                            ConnectionState.waiting
                                        ? 'Loading guide…'
                                        : 'Programme information unavailable'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                borderRadius: BorderRadius.circular(3),
                                color: const Color(0xff64b5f6),
                                backgroundColor: Colors.white24,
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
