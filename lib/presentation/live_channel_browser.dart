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
  final nodes = <String, FocusNode>{};
  final categoryNodes = <String, FocusNode>{};
  final guides = <String, Future<List<EpgProgramme>>>{};
  List<Category> categories = [];
  List<ContentItem> rows = [];
  late Future<void> request;
  String selectedCategory = 'all', query = '';
  String? focusedId, error;
  bool choosingCategory = false, searching = false, busy = false;
  Timer? clock;
  int revision = 0;

  @override
  void initState() {
    super.initState();
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

  List<ContentItem> get visible => rows
      .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
      .toList();
  List<Category> get tabs => [
    const Category('all', 'All', ContentType.live),
    if (widget.provider != null)
      const Category('favorites', 'Favorites', ContentType.live),
    ...categories,
  ];

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
      final index = result.indexWhere(
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

  void focusCategories() {
    if (busy) return;
    setState(() => choosingCategory = true);
    focusCategory(tabs.indexWhere((c) => c.id == selectedCategory));
  }

  void focusCategory(int index) {
    index = index.clamp(0, tabs.length - 1);
    final id = tabs[index].id;
    final target = index * 48.0;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !choosingCategory) return;
      if (categoryScroll.hasClients) {
        categoryScroll.jumpTo(
          target.clamp(0, categoryScroll.position.maxScrollExtent),
        );
      }
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && choosingCategory) categoryNodes[id]?.requestFocus();
    });
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
    clock?.cancel();
    scroll.dispose();
    categoryScroll.dispose();
    for (final node in [...nodes.values, ...categoryNodes.values]) {
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
        width: MediaQuery.sizeOf(context).width * .35,
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
                IconButton(
                  tooltip: 'Search channels',
                  onPressed: () => setState(() => searching = !searching),
                  icon: const Icon(Icons.search, color: Colors.white70),
                ),
              ],
            ),
            if (searching)
              ActivationTextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search channels',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => query = value),
              ),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: tabs
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          backgroundColor: selectedCategory == c.id
                              ? const Color(0xffdce6f2)
                              : const Color(0xff303b48),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: selectedCategory == c.id
                                ? Colors.black87
                                : Colors.white70,
                          ),
                          label: Text(c.name),
                          onPressed: busy ? null : () => loadCategory(c.id),
                        ),
                      ),
                    )
                    .toList(),
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
              child: choosingCategory
                  ? ListView.builder(
                      controller: categoryScroll,
                      itemExtent: 48,
                      itemCount: tabs.length,
                      itemBuilder: (context, index) {
                        final category = tabs[index];
                        return Focus(
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent ||
                                event is KeyRepeatEvent) {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                focusCategory(index - 1);
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                focusCategory(index + 1);
                                return KeyEventResult.handled;
                              }
                            }
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowRight) {
                              returnToChannels();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Material(
                            color: Colors.transparent,
                            child: ListTile(
                              focusNode: categoryNodes.putIfAbsent(
                                category.id,
                                () => FocusNode(),
                              ),
                              title: Text(
                                category.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              selected: category.id == selectedCategory,
                              selectedTileColor: Colors.white12,
                              onFocusChange: (focused) {
                                final target =
                                    categoryNodes[category.id]?.context;
                                if (focused && target != null) {
                                  Scrollable.ensureVisible(target);
                                }
                              },
                              onTap: () => loadCategory(category.id),
                            ),
                          ),
                        );
                      },
                    )
                  : items.isEmpty
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
                            onUp: () => focusChannel(index - 1),
                            onDown: () => focusChannel(index + 1),
                            onLeft: focusCategories,
                            onSelect: busy ? null : () => select(item),
                            onActions: () => actions(item),
                          );
                        },
                      ),
                    ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '↑↓ Browse · ← Categories · OK Watch · Hold OK Actions · Back Close',
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
