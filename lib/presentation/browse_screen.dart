import 'category_sidebar_item.dart';
import 'recordings_library_screen.dart';
import 'live_my_list_panel.dart';
import '../application/live_favourite_groups.dart';
import 'title_access.dart';
import '../application/recent_catalog_cache.dart';
import 'package:flutter/material.dart';
import 'activation_text_field.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'smooth_page_route.dart';
import '../application/appearance.dart';
import '../application/watch_history.dart';
import '../application/my_list.dart';
import '../application/category_locks.dart';
import '../data/locked_provider.dart';
import 'lock_password_dialog.dart';
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
  String liveMyListGroup = LiveFavouriteGroups.all;
  bool? cardsOverride;
  bool get cardMode =>
      cardsOverride ?? widget.appearance?.usesCards(widget.type) ?? false;
  Future<void> toggleView() async {
    final next = !cardMode;
    if (next) {
      final saved = await myList.items(widget.type).then(visibleSavedItems);
      final watching = await history.items(widget.type).then(visibleSavedItems);
      initialMyList = Future.value(saved);
      initialContinue = Future.value(watching);
      preferredInitialRow = saved.isNotEmpty
          ? 0
          : widget.type != ContentType.live && watching.isNotEmpty
          ? 1
          : widget.type != ContentType.live
          ? 2
          : 1;
    }
    if (!mounted) return;
    setState(() {
      cardsOverride = next;
      initialTitleFocused = false;
      initialRevealScheduled = false;
      readyTitleRows.clear();
      emptyCardRows.clear();
    });
    await widget.appearance?.setCards(widget.type, next);
  }

  String categorySort = 'provider', titleSort = 'provider';
  final Map<String, DateTime> categoryDates = {};
  bool sortingCategories = false;
  List<ContentItem> sortTitles(List<ContentItem> source) {
    final result = List<ContentItem>.of(source);
    if (titleSort == 'name') {
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    if (titleSort == 'date') {
      result.sort((a, b) {
        if (a.addedAt == null) return b.addedAt == null ? 0 : 1;
        if (b.addedAt == null) return -1;
        return b.addedAt!.compareTo(a.addedAt!);
      });
    }
    return result;
  }

  List<Category> sortCategories(List<Category> source) {
    final result = List<Category>.of(source);
    if (categorySort == 'name') {
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    if (categorySort == 'date') {
      result.sort(
        (a, b) => (categoryDates[b.id] ?? DateTime(1970)).compareTo(
          categoryDates[a.id] ?? DateTime(1970),
        ),
      );
    }
    return result;
  }

  Future<void> changeCategorySort(String value) async {
    if (sortingCategories) return;
    if (value == 'date') {
      setState(() => sortingCategories = true);
      try {
        final catalog = await RecentCatalogCache.load(
          widget.provider,
          widget.type,
        );
        categoryDates.clear();
        for (final item in catalog) {
          if (item.categoryId != null && item.addedAt != null) {
            final old = categoryDates[item.categoryId!];
            if (old == null || item.addedAt!.isAfter(old)) {
              categoryDates[item.categoryId!] = item.addedAt!;
            }
          }
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
        }
        if (mounted) setState(() => sortingCategories = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      categorySort = value;
      sortingCategories = false;
    });
  }

  Future<void> openRecordings() async {
    await locks.load();
    if (!mounted) return;
    final category = CategoryLocks.recordingsCategory(widget.type);
    if (locks.hidden(category)) return;
    if (locks.isLocked(category)) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => LockPasswordDialog(locks: locks),
      );
      if (!mounted || pin == null || !locks.unlock(category, pin)) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => RecordingsLibraryScreen(
          provider: widget.provider,
          type: widget.type,
        ),
      ),
    );
  }

  Widget recordingsCategory() =>
      locks.hidden(CategoryLocks.recordingsCategory(widget.type))
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Recordings'),
            trailing:
                locks.isLocked(CategoryLocks.recordingsCategory(widget.type))
                ? const Icon(Icons.lock_outline, size: 18)
                : null,
            onTap: openRecordings,
          ),
        );
  Widget sortControl({required bool categories}) => PopupMenuButton<String>(
    tooltip: categories ? 'Sort categories' : 'Sort titles',
    icon: Icon(categories ? Icons.sort_by_alpha : Icons.sort),
    initialValue: categories ? categorySort : titleSort,
    onSelected: (value) {
      if (categories) {
        changeCategorySort(value);
      } else {
        setState(() => titleSort = value);
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'provider', child: Text('Provider order')),
      PopupMenuItem(value: 'name', child: Text('Name (A-Z)')),
      PopupMenuItem(value: 'date', child: Text('Date added (newest first)')),
    ],
  );
  final Map<String, Future<List<ContentItem>>> rowItems = {};
  Future<List<ContentItem>> loadCategory(
    Category category, {
    bool refresh = false,
  }) {
    if (refresh) rowItems.remove(category.id);
    return rowItems
        .putIfAbsent(category.id, () => widget.provider.getItems(category))
        .then(sortTitles);
  }

  bool showingRecent = false;
  bool showingContinue = false;
  bool showingMyList = false;
  int listRevision = 0;
  int lockRevision = 0;
  late final myList = MyList.forProvider(widget.provider);
  late final locks = CategoryLocks.forProvider(widget.provider);
  int historyRevision = 0;
  final cardScroll = ScrollController();
  final Map<int, FocusNode> cardRowNodes = {};
  final Map<(int, int), FocusNode> titleNodes = {};
  FocusNode titleNode(int row, int column) => titleNodes.putIfAbsent((
    row,
    column,
  ), () => FocusNode(debugLabel: 'title $row:$column'));
  Future<List<ContentItem>>? initialMyList;
  Future<List<ContentItem>>? initialContinue;
  int preferredInitialRow = 0;
  bool initialRevealScheduled = false;
  bool initialTitleFocused = false;
  int? pendingTitleRow;
  final Set<int> emptyCardRows = {};
  final Set<int> readyTitleRows = {};
  void emptyRowReady(int row) {
    emptyCardRows.add(row);
    readyTitleRows.remove(row);
  }

  void focusInitialTitle(int row) {
    emptyCardRows.remove(row);
    readyTitleRows.add(row);
    if (!initialTitleFocused) {
      if (!readyTitleRows.contains(preferredInitialRow)) return;
      row = preferredInitialRow;
    }
    if ((initialTitleFocused && pendingTitleRow != row) ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    final node = titleNode(row, 0);
    if (node.context == null) return;
    pendingTitleRow = null;
    initialTitleFocused = true;
    activeCardRow = row;
    node.requestFocus();
    if (cardScroll.hasClients && !movingRows) {
      cardScroll.animateTo(
        (row * 280.0).clamp(0, cardScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
    // Apply once more after Flutter resolves any queued route autofocus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.context != null && activeCardRow == row) {
        node.requestFocus();
      }
    });
  }

  final Map<int, CardRowNavigation> rowNavigation = {};
  CardRowNavigation navigationFor(int row) =>
      rowNavigation.putIfAbsent(row, () => CardRowNavigation());
  bool movingRows = false;
  FocusNode rowNode(int index) => cardRowNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'category row $index'),
  );
  Future<void> moveRow(int target) async {
    if (movingRows || !cardScroll.hasClients) return;
    movingRows = true;
    pendingTitleRow = target;
    try {
      await cardScroll.animateTo(
        (target * 280.0).clamp(0, cardScroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
      if (!mounted) return;
      final focused = await navigationFor(target).focusFirst?.call() ?? false;
      if (focused) pendingTitleRow = null;
    } finally {
      movingRows = false;
    }
  }

  int cardRowCount = 0;
  int? activeCardRow;
  bool cardRemoteKeys(KeyEvent event) {
    if (!mounted ||
        !cardMode ||
        ModalRoute.of(context)?.isCurrent != true ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return false;
    }
    final step = event.logicalKey == LogicalKeyboardKey.arrowDown
        ? 1
        : event.logicalKey == LogicalKeyboardKey.arrowUp
        ? -1
        : 0;
    final focus = FocusManager.instance.primaryFocus;
    int? row;
    for (final entry in titleNodes.entries) {
      if (entry.value.hasPrimaryFocus) {
        row = entry.key.$1;
        break;
      }
    }
    row ??= cardRowNodes.entries
        .where((entry) => entry.value.hasPrimaryFocus)
        .map((entry) => entry.key)
        .firstOrNull;
    row ??= focus?.ancestors
        .where((node) => node.debugLabel?.startsWith('card group ') == true)
        .map((node) => int.tryParse(node.debugLabel!.substring(11)))
        .whereType<int>()
        .firstOrNull;
    if (row != null &&
        step == 1 &&
        titleNodes.entries.any(
          (entry) => entry.key.$1 == row && entry.value.hasPrimaryFocus,
        )) {
      activeCardRow = row;
      rowNode(row).requestFocus();
      return true;
    }
    if (row != null && step == -1 && rowNode(row).hasPrimaryFocus) {
      navigationFor(row).focusFirst?.call();
      return true;
    }
    if (row != null &&
        event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        rowNode(row).hasPrimaryFocus) {
      final titles =
          titleNodes.entries
              .where(
                (entry) => entry.key.$1 == row && entry.value.context != null,
              )
              .toList()
            ..sort((a, b) => b.key.$2.compareTo(a.key.$2));
      if (titles.isNotEmpty) {
        titles.first.value.requestFocus();
        return true;
      }
    }
    if (step == 0) return false;
    // A lazy row can be detached while scrolling. Retain its index so Up can
    // recover focus rather than handing navigation to the root focus scope.
    if (focus is FocusScopeNode) row ??= activeCardRow;
    if (row == null) return false;
    var next = row + step;
    while (next >= 0 && next < cardRowCount && emptyCardRows.contains(next)) {
      next += step;
    }
    if (next < 0 || next >= cardRowCount) return true;
    activeCardRow = next;
    moveRow(next);
    return true;
  }

  late final history = WatchHistory.forProvider(widget.provider);
  Future<List<ContentItem>>? recentCatalog;
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(cardRemoteKeys);
    categories = widget.provider.getCategories(widget.type).then((rows) async {
      await locks.load();
      if (cardMode) {
        // Resolve the small local lists before choosing initial focus. Network
        // completion order must never let Recently Added bypass saved titles.
        final saved = await myList.items(widget.type).then(visibleSavedItems);
        final watching = await history
            .items(widget.type)
            .then(visibleSavedItems);
        initialMyList = Future.value(saved);
        initialContinue = Future.value(watching);
        preferredInitialRow = saved.isNotEmpty
            ? 0
            : widget.type != ContentType.live && watching.isNotEmpty
            ? 1
            : widget.type != ContentType.live
            ? 2
            : 1;
      }
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
      initialContinue = null;
      emptyCardRows.remove(1);
      readyTitleRows.remove(1);
      historyRevision++;
      if (showingContinue) {
        items = history.items(widget.type).then(visibleSavedItems);
      }
    });
  }

  void myListChanged() {
    if (!mounted) return;
    setState(() {
      initialMyList = null;
      emptyCardRows.remove(0);
      readyTitleRows.remove(0);
      listRevision++;
      if (showingMyList) {
        items = myList.items(widget.type).then(visibleSavedItems);
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(cardRemoteKeys);
    cardScroll.dispose();
    for (final node in titleNodes.values) {
      node.dispose();
    }
    for (final node in cardRowNodes.values) {
      node.dispose();
    }
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
    RecentCatalogCache.invalidate(widget.provider);
    setState(() {
      categories = widget.provider.getCategories(widget.type);
      lockRevision++;
      rowItems.clear();
      recentCatalog = null;
      listRevision++;
      historyRevision++;
      if (showingRecent) {
        recentCatalog = RecentCatalogCache.load(
          widget.provider,
          widget.type,
          refresh: true,
        );
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
    recentCatalog ??= RecentCatalogCache.load(
      widget.provider,
      widget.type,
      refresh: refresh,
    );
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
          IconButton(
            tooltip: cardMode
                ? 'Use category list view'
                : 'Use horizontal cards view',
            icon: Icon(
              cardMode
                  ? Icons.view_list_outlined
                  : Icons.view_carousel_outlined,
            ),
            onPressed: toggleView,
          ),
          sortControl(categories: true),
          sortControl(categories: false),
          if (sortingCategories)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Tooltip(
              message: 'Search all categories',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(110, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Search all'),
                onPressed: () => Navigator.of(context).push(
                  SmoothPageRoute<void>(
                    builder: (_) => CatalogSearchScreen(
                      provider: widget.provider,
                      type: widget.type,
                      onOpen: openItem,
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
                SizedBox(width: 320, child: categoryList()),
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
    builder: (unsortedRows) {
      final rows = sortCategories(unsortedRows);
      final hasRecent = widget.type != ContentType.live;
      cardRowCount = rows.length + (hasRecent ? 2 : 0) + 1;
      if (!initialRevealScheduled) {
        initialRevealScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !initialTitleFocused) moveRow(preferredInitialRow);
        });
      }
      return Column(
        children: [
          recordingsCategory(),
          Expanded(
            child: ListView.builder(
              key: ValueKey((categorySort, titleSort)),
              controller: cardScroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(338),
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: rows.length + (hasRecent ? 2 : 0) + 1,
              itemExtent: 280,
              itemBuilder: (_, index) => Focus(
                canRequestFocus: false,
                debugLabel: 'card group $index',
                child: buildCardRow(rows, index),
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget buildCardRow(List<Category> rows, int index) {
    final rowIndex = index;
    final hasRecent = widget.type != ContentType.live;

    if (index == 0) {
      return CategoryCardRow(
        entryFocusNode: rowNode(rowIndex),
        navigation: navigationFor(rowIndex),
        itemFocusNode: (column) => titleNode(rowIndex, column),
        onTitleReady: () => focusInitialTitle(rowIndex),
        onEmpty: () => emptyRowReady(rowIndex),
        key: ValueKey('my-list:$listRevision'),
        title: 'My list',
        load: (_) =>
            initialMyList ?? myList.items(widget.type).then(visibleSavedItems),
        onMore: selectMyList,
        onOpen: openItem,
      );
    }
    index--;
    if (hasRecent && index == 0) {
      return CategoryCardRow(
        entryFocusNode: rowNode(rowIndex),
        navigation: navigationFor(rowIndex),
        itemFocusNode: (column) => titleNode(rowIndex, column),
        onTitleReady: () => focusInitialTitle(rowIndex),
        onEmpty: () => emptyRowReady(rowIndex),
        key: ValueKey('continue-row:$historyRevision'),
        title: 'Continue watching',
        load: (_) =>
            initialContinue ??
            history.items(widget.type).then(visibleSavedItems),
        onMore: selectContinue,
        onOpen: openItem,
      );
    }
    if (hasRecent && index == 1) {
      return CategoryCardRow(
        entryFocusNode: rowNode(rowIndex),
        navigation: navigationFor(rowIndex),
        itemFocusNode: (column) => titleNode(rowIndex, column),
        onTitleReady: () => focusInitialTitle(rowIndex),
        onEmpty: () => emptyRowReady(rowIndex),
        key: ValueKey('recent-row:$lockRevision'),
        title: 'Recently added',
        load: (refresh) {
          if (refresh) recentCatalog = null;
          return recentCatalog ??= RecentCatalogCache.load(
            widget.provider,
            widget.type,
            refresh: refresh,
          );
        },
        onMore: selectRecent,
        onOpen: openItem,
      );
    }
    final category = rows[index - (hasRecent ? 2 : 0)];
    if (locks.isLocked(category)) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: FocusCard(
          focusNode: rowNode(rowIndex),
          onTap: () => select(category),
          child: Row(
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(width: 12),
              Expanded(child: Text(category.name)),
            ],
          ),
        ),
      );
    }
    return CategoryCardRow(
      entryFocusNode: rowNode(rowIndex),
      navigation: navigationFor(rowIndex),
      itemFocusNode: (column) => titleNode(rowIndex, column),
      onTitleReady: () => focusInitialTitle(rowIndex),
      onEmpty: () => emptyRowReady(rowIndex),
      key: ValueKey(
        lockRevision == 0
            ? 'category-row:${category.id}'
            : 'category-row:${category.id}:$lockRevision',
      ),
      title: category.name,
      load: (refresh) => loadCategory(category, refresh: refresh),
      onMore: () => select(category),
      onOpen: openItem,
    );
  }

  Widget categoryList() => AsyncView(
    future: categories,
    retry: () => setState(() {
      categories = widget.provider.getCategories(widget.type);
    }),
    builder: (unsortedRows) {
      final rows = sortCategories(unsortedRows);
      final recordings = CategoryLocks.recordingsCategory(widget.type);
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!locks.hidden(recordings))
            CategorySidebarItem(
              label: 'Recordings',
              locked: locks.isLocked(recordings),
              onTap: openRecordings,
            ),
          CategorySidebarItem(
            label: 'My list',
            selected: showingMyList && selected != null,
            onTap: selectMyList,
          ),
          if (widget.type != ContentType.live) ...[
            CategorySidebarItem(
              label: 'Continue watching',
              selected: showingContinue && selected != null,
              onTap: selectContinue,
            ),
            CategorySidebarItem(
              label: 'Recently added',
              selected: showingRecent && selected != null,
              onTap: selectRecent,
            ),
          ],
          for (var index = 0; index < rows.length; index++)
            CategorySidebarItem(
              key: ValueKey('sidebar:${rows[index].id}'),
              label: rows[index].name,
              locked: locks.isLocked(rows[index]),
              selected:
                  !showingMyList &&
                  !showingRecent &&
                  !showingContinue &&
                  selected?.id == rows[index].id,
              onTap: () => select(rows[index]),
            ),
          if (rows.isEmpty) const EmptyState('No categories available'),
        ],
      );
    },
  );

  Widget itemList() => showingMyList && widget.type == ContentType.live
      ? LiveMyListPanel(
          provider: widget.provider,
          selectedGroup: liveMyListGroup,
          onGroupChanged: (id) => setState(() => liveMyListGroup = id),
          onPlay: openItem,
        )
      : Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected!.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ActivationTextField(
                    key: ValueKey(selected!.id),
                    decoration: const InputDecoration(
                      hintText: 'Search this category',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      prefixIcon: Icon(Icons.search, size: 18),
                      prefixIconConstraints: BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
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
                    : setState(
                        () => items = loadCategory(selected!, refresh: true),
                      ),
                builder: (rows) {
                  final filtered = sortTitles(rows)
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
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisExtent: widget.type == ContentType.live
                          ? 150
                          : 235,
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
                                child: item.type == ContentType.live
                                    ? ChannelLogo(item.artwork)
                                    : Artwork(item.artwork),
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
    if (!await requestTitleAccess(context, widget.provider, item) || !mounted) {
      return;
    }
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
            provider: widget.provider,
            item: item,
            channelCategory: favourites
                ? 'My List - ${LiveFavouriteGroups.forProvider(widget.provider).name(liveMyListGroup)}'
                : category?.name ?? 'Channels',
            loadChannels: () => favourites
                ? () async {
                    final groups = LiveFavouriteGroups.forProvider(
                      widget.provider,
                    );
                    await groups.load();
                    final saved = await myList
                        .items(ContentType.live)
                        .then(visibleSavedItems);
                    return groups.channels(liveMyListGroup, saved);
                  }()
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
