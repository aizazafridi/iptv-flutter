import '../application/live_favourite_groups.dart';
import 'live_favourite_dialogs.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/category_locks.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'activation_text_field.dart';
import 'lock_password_dialog.dart';
import 'my_list_button.dart';
import 'widgets.dart';

/// Browsing owns only UI state: the existing player keeps its engine and surface.
class LiveChannelBrowser extends StatefulWidget {
  final Future<List<ContentItem>> Function() load;
  final IptvProvider? provider;
  final String? currentId, categoryId;
  final Future<bool> Function(ContentItem)? onSelect;
  const LiveChannelBrowser({
    super.key,
    required this.load,
    this.provider,
    this.currentId,
    this.categoryId,
    this.onSelect,
  });
  @override
  State<LiveChannelBrowser> createState() => _LiveChannelBrowserState();
}

class _LiveChannelBrowserState extends State<LiveChannelBrowser> {
  static const rowHeight = 86.0;
  final scroll = ScrollController();
  final categoryScroll = ScrollController();
  final myListFocus = FocusNode(debugLabel: 'channel My List');
  final nodes = <String, FocusNode>{};
  final groupNodes = <String, FocusNode>{};
  final categoryNodes = <String, FocusNode>{};
  final guides = <String, Future<List<EpgProgramme>>>{};
  List<Category> categories = [];
  List<ContentItem> rows = [];
  late Future<void> request;
  String selectedCategory = 'all', query = '';
  String? focusedId, error;
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
    if (categories.any((c) => c.id == widget.categoryId)) {
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

  List<ContentItem> get visible => selectedCategory == 'favorites'
      ? groups!.channels(groups!.selectedGroup, rows)
      : rows;
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

  double get categoryWidth {
    var width = 126.0;
    for (final category in tabs) {
      final painter = TextPainter(
        text: TextSpan(
          text: category.name,
          style: const TextStyle(fontSize: 12),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      if (painter.width + 38 > width) width = painter.width + 38;
      painter.dispose();
    }
    return width;
  }

  void focusCategories() {
    if (busy) return;
    setState(() => choosingCategory = true);
    focusCategory(tabs.indexWhere((c) => c.id == selectedCategory));
  }

  void focusCategory(int index) {
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
    groupNodes[id]?.requestFocus();
  }

  void returnToChannels() {
    setState(() => choosingCategory = false);
    final index = visible.indexWhere((c) => c.id == focusedId);
    focusChannel(index < 0 ? 0 : index);
  }

  Future<void> select(ContentItem item) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final success = widget.onSelect == null || await widget.onSelect!(item);
      if (!mounted) return;
      if (success) {
        Navigator.pop(context, item);
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name, style: const TextStyle(fontSize: 18)),
        content: MyListButton(provider: widget.provider!, item: item),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) focusChannel(visible.indexWhere((c) => c.id == item.id));
  }

  Future<List<EpgProgramme>> guide(ContentItem item) =>
      guides.putIfAbsent(item.id, () async {
        try {
          final provider = widget.provider;
          return provider is EpgProvider
              ? await (provider as EpgProvider).getEpg(item)
              : [];
        } catch (_) {
          return [];
        }
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
    for (final node in [
      myListFocus,
      ...nodes.values,
      ...categoryNodes.values,
      ...groupNodes.values,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = visible;
    return Dialog(
      alignment: Alignment.centerLeft,
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        key: const ValueKey('live-channel-browser-panel'),
        width: MediaQuery.sizeOf(context).width * .45,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xf21a2029),
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
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : focusCategories,
                  icon: const Icon(Icons.folder_outlined, size: 16),
                  label: const Text(
                    'Categories',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Search categories',
                  onPressed: () => setState(() {
                    searching = !searching;
                    if (!searching) query = '';
                  }),
                  icon: const Icon(Icons.search, color: Colors.white70),
                ),
              ],
            ),
            if (searching)
              ActivationTextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search categories',
                  isDense: true,
                ),
                onChanged: (value) => setState(() {
                  query = value;
                  if (categoryScroll.hasClients) categoryScroll.jumpTo(0);
                }),
              ),
            SizedBox(
              height: 42,
              child: ListView.builder(
                controller: categoryScroll,
                scrollDirection: Axis.horizontal,
                itemExtent: categoryWidth,
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final category = tabs[index];
                  final categoryFocus = categoryNodes.putIfAbsent(
                    category.id,
                    () => FocusNode(
                      debugLabel: 'channel category ${category.id}',
                    ),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Focus(
                      focusNode: categoryFocus,
                      onKeyEvent: (_, event) {
                        if (event is! KeyDownEvent &&
                            event is! KeyRepeatEvent) {
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
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (widget.provider != null) {
                            myListFocus.requestFocus();
                          } else {
                            returnToChannels();
                          }
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
                      child: ListenableBuilder(
                        listenable: categoryFocus,
                        builder: (context, _) => Material(
                          borderRadius: BorderRadius.circular(9),
                          color: categoryFocus.hasFocus
                              ? const Color(0xff354962)
                              : category.id == selectedCategory
                              ? const Color(0xff293546)
                              : const Color(0xff202935),
                          child: InkWell(
                            canRequestFocus: false,
                            borderRadius: BorderRadius.circular(9),
                            onTap: busy
                                ? null
                                : () => loadCategory(category.id),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: categoryFocus.hasFocus
                                      ? const Color(0xff9acaff)
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.provider != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      focusCategories();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      if (selectedCategory == 'favorites') {
                        focusGroups();
                      } else {
                        returnToChannels();
                      }
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextButton.icon(
                    focusNode: myListFocus,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: selectedCategory == 'favorites'
                          ? const Color(0xff30465d)
                          : const Color(0xff202935),
                    ),
                    onPressed: busy ? null : () => loadCategory('favorites'),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text(
                      'My List',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            if (selectedCategory == 'favorites')
              SizedBox(
                height: 42,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final id in [
                        LiveFavouriteGroups.all,
                        ...groups!.groups.map((g) => g.id),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowDown) {
                                returnToChannels();
                                return KeyEventResult.handled;
                              }
                              if (event is KeyDownEvent &&
                                  event.logicalKey ==
                                      LogicalKeyboardKey.arrowUp) {
                                myListFocus.requestFocus();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: ChoiceChip(
                              focusNode: groupNodes.putIfAbsent(
                                id,
                                () => FocusNode(),
                              ),
                              label: Text(
                                id == LiveFavouriteGroups.all
                                    ? 'All My List'
                                    : groups!.name(id),
                                style: const TextStyle(fontSize: 11),
                              ),
                              selected:
                                  (groups!.exists(groups!.selectedGroup)
                                      ? groups!.selectedGroup
                                      : LiveFavouriteGroups.all) ==
                                  id,
                              onSelected: (_) => setState(() {
                                groups!.selectedGroup = id;
                                if (scroll.hasClients) scroll.jumpTo(0);
                              }),
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => showLiveGroupName(context, groups!),
                        child: const Text('+ New Group'),
                      ),
                      TextButton(
                        onPressed: () =>
                            showLiveGroupManager(context, widget.provider!),
                        child: const Text('Manage Groups'),
                      ),
                    ],
                  ),
                ),
              ),
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
                        itemExtent: rowHeight,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ChannelRow(
                            key: ValueKey(item.id),
                            item: item,
                            number: rows.indexOf(item) + 1,
                            current: widget.currentId == item.id,
                            node: nodes.putIfAbsent(item.id, () => FocusNode()),
                            epg: guide(item),
                            onFocus: () => focusedId = item.id,
                            onUp: () => index == 0
                                ? (selectedCategory == 'favorites'
                                      ? focusGroups()
                                      : focusCategories())
                                : focusChannel(index - 1),
                            onDown: () => focusChannel(index + 1),
                            onLeft: focusCategories,
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
                    ? 'Categories: Left/Right browse, OK select, Down channels'
                    : 'Channels: Up/Down browse, Left categories, OK watch, Back close',
                maxLines: 2,
                style: TextStyle(fontSize: 10, color: Colors.white60),
              ),
            ),
          ],
        ),
      ),
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
