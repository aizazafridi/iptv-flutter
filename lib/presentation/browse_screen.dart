import 'package:flutter/material.dart';
import 'smooth_page_route.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../application/recent_items.dart';
import '../application/appearance.dart';
import '../application/watch_history.dart';
import '../application/my_list.dart';
import '../application/category_locks.dart';
import '../data/locked_provider.dart';
import 'lock_password_dialog.dart';
import 'my_list_button.dart';
import 'category_card_row.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'widgets.dart';
import 'search_screen.dart';

class BrowseScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  final AppAppearance? appearance;
  const BrowseScreen({
    super.key,
    required this.provider,
    required this.type,
    this.appearance,
  });
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late Future<List<Category>> categories;
  Future<List<ContentItem>>? items;
  Category? selected;
  String search = '';
  bool get cardMode => widget.appearance?.usesCards(widget.type) ?? false;
  final Map<String, Future<List<ContentItem>>> rowItems = {};
  Future<List<ContentItem>> loadCategory(
    Category category, {
    bool refresh = false,
  }) {
    if (refresh) rowItems.remove(category.id);
    return rowItems.putIfAbsent(
      category.id,
      () => widget.provider.getItems(category),
    );
  }

  bool showingRecent = false;
  bool showingContinue = false;
  bool showingMyList = false;
  int listRevision = 0;
  int lockRevision = 0;
  late final myList = MyList.forProvider(widget.provider);
  late final locks = CategoryLocks.forProvider(widget.provider);
  int historyRevision = 0;
  late final history = WatchHistory.forProvider(widget.provider);
  Future<List<ContentItem>>? recentCatalog;
  @override
  void initState() {
    super.initState();
    categories = widget.provider.getCategories(widget.type).then((rows) async {
      await locks.load();
      return rows;
    });
    myList.addListener(myListChanged);
    history.addListener(historyChanged);
    locks.addListener(locksChanged);
  }

  Future<List<ContentItem>> visibleSavedItems(List<ContentItem> rows) =>
      widget.provider is LockedProvider
      ? (widget.provider as LockedProvider).visibleSavedItems(rows)
      : locks.visibleItems(rows);
  void historyChanged() {
    if (!mounted) return;
    setState(() {
      historyRevision++;
      if (showingContinue) {
        items = history.items(widget.type).then(visibleSavedItems);
      }
    });
  }

  void myListChanged() {
    if (!mounted) return;
    setState(() {
      listRevision++;
      if (showingMyList) {
        items = myList.items(widget.type).then(visibleSavedItems);
      }
    });
  }

  @override
  void dispose() {
    myList.removeListener(myListChanged);
    history.removeListener(historyChanged);
    locks.removeListener(locksChanged);
    super.dispose();
  }

  void selectMyList() => setState(() {
    showingMyList = true;
    showingRecent = false;
    showingContinue = false;
    selected = Category('__my_list__', 'My list', widget.type);
    items = myList.items(widget.type).then(visibleSavedItems);
    search = '';
  });
  void locksChanged() {
    if (!mounted) return;
    setState(() {
      lockRevision++;
      rowItems.clear();
      recentCatalog = null;
      listRevision++;
      historyRevision++;
      if (showingRecent) {
        recentCatalog = widget.provider
            .getAllItems(widget.type)
            .then(recentlyAdded);
        items = recentCatalog;
      }
      if (selected != null &&
          !selected!.id.startsWith('__') &&
          locks.isLocked(selected!)) {
        selected = null;
        items = null;
      }
      if (showingMyList) {
        items = myList.items(widget.type).then(visibleSavedItems);
      }
      if (showingContinue) {
        items = history.items(widget.type).then(visibleSavedItems);
      }
    });
  }

  Widget lockButton(Category category) => IconButton(
    tooltip: locks.configured(category)
        ? 'Remove category lock'
        : 'Lock category',
    icon: Icon(
      locks.configured(category) ? Icons.lock : Icons.lock_open_outlined,
    ),
    onPressed: () async {
      try {
        String password = '';
        if (locks.configured(category)) {
          final value = await showDialog<String>(
            context: context,
            builder: (_) => LockPasswordDialog(locks: locks),
          );
          if (value == null) return;
          password = value;
        }
        await locks.setLocked(
          category,
          !locks.configured(category),
          password: password,
        );
      } catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(safeMessage(exception))));
        }
      }
    },
  );
  Future<void> select(Category category) async {
    await locks.load();
    if (!mounted) return;
    if (locks.isLocked(category)) {
      final password = await showDialog<String>(
        context: context,
        builder: (_) => LockPasswordDialog(locks: locks),
      );
      if (!mounted || password == null || !locks.unlock(category, password)) {
        return;
      }
    }
    setState(() {
      showingMyList = false;
      showingRecent = false;
      showingContinue = false;
      selected = category;
      items = loadCategory(category);
      search = '';
    });
  }

  void selectRecent({bool refresh = false}) => setState(() {
    showingMyList = false;
    showingRecent = true;
    showingContinue = false;
    selected = Category('__recent__', 'Recently added', widget.type);
    if (refresh) recentCatalog = null;
    recentCatalog ??= widget.provider
        .getAllItems(widget.type)
        .then(recentlyAdded);
    items = recentCatalog;
    search = '';
  });
  void selectContinue() => setState(() {
    showingMyList = false;
    showingContinue = true;
    showingRecent = false;
    selected = Category('__continue__', 'Continue watching', widget.type);
    items = history.items(widget.type).then(visibleSavedItems);
    search = '';
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop:
        selected == null ||
        (!cardMode && MediaQuery.sizeOf(context).width >= 700),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        setState(() {
          selected = null;
          items = null;
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.type.label),
        actions: [
          if (widget.type != ContentType.live)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: 'Search all categories',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.search, size: 28),
                  label: const Text('Search all'),
                  onPressed: () => Navigator.of(context).push(
                    SmoothPageRoute<void>(
                      builder: (_) => CatalogSearchScreen(
                        provider: widget.provider,
                        type: widget.type,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        leading: BackButton(
          onPressed: () {
            if (selected != null &&
                (cardMode || MediaQuery.sizeOf(context).width < 700)) {
              setState(() {
                selected = null;
                items = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: LayoutBuilder(
          key: ValueKey(
            cardMode
                ? (selected == null ? 'rows' : 'category')
                : (MediaQuery.sizeOf(context).width < 700 && selected != null
                      ? 'category'
                      : 'browse'),
          ),
          builder: (context, constraints) {
            if (cardMode) {
              return selected == null ? cardCategories() : itemList();
            }
            if (constraints.maxWidth < 700) {
              return selected == null ? categoryList() : itemList();
            }
            return Row(
              children: [
                SizedBox(
                  width: widget.type == ContentType.live ? 320 : 260,
                  child: categoryList(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: selected == null
                      ? const EmptyState('Choose a category')
                      : itemList(),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget cardCategories() => AsyncView(
    future: categories,
    retry: () =>
        setState(() => categories = widget.provider.getCategories(widget.type)),
    builder: (rows) {
      final hasRecent = widget.type != ContentType.live;

      return ListView.builder(
        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: rows.length + (hasRecent ? 2 : 0) + 1,
        itemBuilder: (_, index) {
          if (index == 0) {
            return CategoryCardRow(
              key: ValueKey('my-list:$listRevision'),
              title: 'My list',
              load: (_) => myList.items(widget.type).then(visibleSavedItems),
              onMore: selectMyList,
              onOpen: openItem,
              itemAction: (item) =>
                  MyListButton(provider: widget.provider, item: item),
            );
          }
          index--;
          if (hasRecent && index == 0) {
            return CategoryCardRow(
              key: ValueKey('continue-row:$historyRevision'),
              title: 'Continue watching',
              load: (_) => history.items(widget.type).then(visibleSavedItems),
              onMore: selectContinue,
              onOpen: openItem,
              itemAction: (item) =>
                  MyListButton(provider: widget.provider, item: item),
            );
          }
          if (hasRecent && index == 1) {
            return CategoryCardRow(
              key: ValueKey('recent-row:$lockRevision'),
              title: 'Recently added',
              load: (refresh) {
                if (refresh) recentCatalog = null;
                return recentCatalog ??= widget.provider
                    .getAllItems(widget.type)
                    .then(recentlyAdded);
              },
              onMore: selectRecent,
              onOpen: openItem,
              itemAction: (item) =>
                  MyListButton(provider: widget.provider, item: item),
            );
          }
          final category = rows[index - (hasRecent ? 2 : 0)];
          if (locks.isLocked(category)) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: FocusCard(
                onTap: () => select(category),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline),
                    const SizedBox(width: 12),
                    Expanded(child: Text(category.name)),
                    lockButton(category),
                  ],
                ),
              ),
            );
          }
          return CategoryCardRow(
            key: ValueKey(
              lockRevision == 0
                  ? 'category-row:${category.id}'
                  : 'category-row:${category.id}:$lockRevision',
            ),
            headerAction: lockButton(category),
            title: category.name,
            load: (refresh) => loadCategory(category, refresh: refresh),
            onMore: () => select(category),
            onOpen: openItem,
            itemAction: (item) =>
                MyListButton(provider: widget.provider, item: item),
          );
        },
      );
    },
  );

  Widget categoryList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: FocusCard(
          padding: widget.type == ContentType.live
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 2)
              : const EdgeInsets.all(14),
          selected: showingMyList && selected != null,
          onTap: selectMyList,
          child: widget.type == ContentType.live
              ? const SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('My list'),
                  ),
                )
              : const Text('My list'),
        ),
      ),
      if (widget.type != ContentType.live)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: FocusCard(
            selected: showingContinue && selected != null,
            onTap: selectContinue,
            child: const Text('Continue watching'),
          ),
        ),
      if (widget.type != ContentType.live)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: FocusCard(
            autofocus: true,
            selected: showingRecent && selected != null,
            onTap: selectRecent,
            child: const Row(
              children: [
                Icon(Icons.new_releases_outlined),
                SizedBox(width: 8),
                Expanded(child: Text('Recently added')),
              ],
            ),
          ),
        ),
      Expanded(
        child: AsyncView(
          future: categories,
          retry: () => setState(() {
            categories = widget.provider.getCategories(widget.type);
          }),
          builder: (rows) => rows.isEmpty
              ? const EmptyState('No categories available')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  itemBuilder: (_, index) {
                    final category = rows[index];
                    return FocusCard(
                      padding: widget.type == ContentType.live
                          ? const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 2,
                            )
                          : const EdgeInsets.all(14),
                      autofocus: index == 0 && widget.type == ContentType.live,
                      selected:
                          !showingMyList &&
                          !showingRecent &&
                          !showingContinue &&
                          selected?.id == category.id,
                      onTap: () => select(category),
                      child: Row(
                        children: [
                          Expanded(child: Text(category.name)),
                          lockButton(category),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    ],
  );

  Widget itemList() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected!.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(selected!.id),
              decoration: const InputDecoration(
                hintText: 'Search this category',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => search = value.toLowerCase()),
            ),
          ],
        ),
      ),
      Expanded(
        child: AsyncView(
          future: items!,
          retry: () => showingMyList
              ? selectMyList()
              : showingContinue
              ? selectContinue()
              : showingRecent
              ? selectRecent(refresh: true)
              : setState(() => items = loadCategory(selected!, refresh: true)),
          builder: (rows) {
            final filtered = rows
                .where((item) => item.name.toLowerCase().contains(search))
                .toList();
            if (filtered.isEmpty) {
              return EmptyState(
                showingRecent && rows.isEmpty
                    ? 'No dated additions available from the provider.'
                    : 'No items found',
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 285,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final item = filtered[index];
                return FocusCard(
                  autofocus: index == 0,
                  onTap: () => openItem(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: Artwork(item.artwork),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          MyListButton(provider: widget.provider, item: item),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> openItem(ContentItem item) async {
    if (item.type != ContentType.live) {
      await Navigator.of(context).push(
        SmoothPageRoute<void>(
          builder: (_) => DetailsScreen(provider: widget.provider, item: item),
        ),
      );
      if (mounted) {
        setState(() {
          historyRevision++;
          if (showingContinue) {
            items = history.items(widget.type).then(visibleSavedItems);
          }
        });
      }
      return;
    }
    try {
      final source = await widget.provider.resolvePlayback(item);
      final category = selected != null && !selected!.id.startsWith('__')
          ? selected
          : item.categoryId == null
          ? null
          : (await categories)
                .where((c) => c.id == item.categoryId)
                .firstOrNull;
      final favourites = showingMyList;
      if (!mounted) return;
      await Navigator.of(context).push(
        SmoothPageRoute<void>(
          builder: (_) => PlayerScreen(
            source: source,
            item: item,
            channelCategory: favourites
                ? 'My list'
                : category?.name ?? 'Channels',
            loadChannels: () => favourites
                ? myList.items(ContentType.live).then(visibleSavedItems)
                : category != null
                ? loadCategory(category)
                : widget.provider.getAllItems(ContentType.live),
            resolveChannel: (channel) =>
                widget.provider.resolvePlayback(channel),
            channelEpg: widget.provider is EpgProvider
                ? (channel) => (widget.provider as EpgProvider).getEpg(channel)
                : null,
            loadEpg: widget.provider is EpgProvider
                ? () => (widget.provider as EpgProvider).getEpg(item)
                : null,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    }
  }
}
