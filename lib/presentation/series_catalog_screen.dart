import 'artwork_prefetch.dart';
import 'catalog_categories_drawer.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../application/category_locks.dart';
import '../application/recent_catalog_cache.dart';
import '../application/recent_items.dart';
import '../application/watch_history.dart';
import '../application/my_list.dart';
import '../data/tmdb_artwork_service.dart';
import '../data/tmdb_cast_service.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'activation_text_field.dart';
import 'catalog_poster_artwork.dart';
import 'continue_watching_artwork.dart';
import 'details_screen.dart';
import 'media_horizontal_rail.dart';
import 'search_screen.dart';
import 'smooth_page_route.dart';
import 'title_access.dart';

const _blue = Color(0xff64b5f6);
const _background = Color(0xff0b1018);

/// Embedded in the existing dashboard so its navigation rail stays available.
class SeriesCatalogScreen extends StatefulWidget {
  final ContentType type;
  final IptvProvider provider;
  final VoidCallback onNavigation, onSettings;
  final List<Widget> headerActions;
  const SeriesCatalogScreen({
    super.key,
    required this.provider,
    this.type = ContentType.series,
    required this.onNavigation,
    required this.onSettings,
    this.headerActions = const [],
  });
  @override
  State<SeriesCatalogScreen> createState() => SeriesCatalogScreenState();
}

class SeriesCatalogScreenState extends State<SeriesCatalogScreen> {
  bool get movies => widget.type == ContentType.movies;
  String get catalogName => movies ? 'Movies' : 'Series';
  String get catalogLower => movies ? 'movies' : 'series';
  late final history = WatchHistory.forProvider(widget.provider);
  late final myList = MyList.forProvider(widget.provider);
  List<ContentItem> savedTitles = [];
  int savedRevision = 0;
  late final locks = CategoryLocks.forProvider(widget.provider);
  final page = ScrollController();
  final gridQueryController = TextEditingController();
  final categoriesFocus = FocusNode(debugLabel: 'catalog categories');
  final searchFocus = FocusNode(debugLabel: 'series catalog search');
  final detailsFocus = FocusNode(debugLabel: 'series featured details');
  final watchFocus = FocusNode(debugLabel: 'series featured watch');
  final gridSearch = FocusNode(debugLabel: 'series grid search');
  final gridSortMenu = GlobalKey<PopupMenuButtonState<String>>();
  final gridSort = FocusNode(debugLabel: 'catalog grid sort');
  final gridCatalog = FocusNode(debugLabel: 'catalog grid catalog');
  final footerFocus = FocusNode(debugLabel: 'series catalog all series');
  bool focusOnReady = false;
  final gridFirst = FocusNode(debugLabel: 'series grid first poster');
  final categoryData = <String, Future<List<ContentItem>>>{};
  final detailData = <String, Future<SeriesDetails>>{};
  final _rowKeys = <String, GlobalKey<_CatalogSectionState>>{};
  final emptyRows = <String>{};
  List<Category> categories = [];
  List<ContentItem> seed = [];
  List<WatchEntry> watching = [];
  ContentItem? featured;
  Timer? featuredTimer;
  bool loading = true, failed = false, grid = false;
  String? filter;
  String query = '', sort = 'provider';
  Future<List<ContentItem>>? gridItems;
  int generation = 0;
  double rowExtent = 320, heroExtent = 300, posterWidth = 130;
  double _extentFor(_Section section) =>
      section.landscape ? posterWidth * 1.7 * 9 / 16 + 135 : rowExtent;
  GlobalKey<_CatalogSectionState> _rowKey(String id) =>
      _rowKeys.putIfAbsent(id, () => GlobalKey<_CatalogSectionState>());
  @override
  void initState() {
    super.initState();
    history.addListener(historyChanged);
    myList.addListener(myListChanged);
    locks.addListener(restrictionsChanged);
    unawaited(load());
    featuredTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted ||
          loading ||
          grid ||
          watching.length < 2 ||
          !TickerMode.valuesOf(context).enabled ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final index = watching.indexWhere(
        (entry) => entry.item.id == featured?.id,
      );
      setState(() => featured = watching[(index + 1) % watching.length].item);
    });
  }

  @override
  void dispose() {
    featuredTimer?.cancel();
    history.removeListener(historyChanged);
    myList.removeListener(myListChanged);
    locks.removeListener(restrictionsChanged);
    page.dispose();
    gridQueryController.dispose();
    for (final node in [
      categoriesFocus,
      searchFocus,
      detailsFocus,
      watchFocus,
      gridSearch,
      gridSort,
      gridCatalog,
      gridFirst,
      footerFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<List<ContentItem>> allowed(List<ContentItem> rows) async {
    final visible = await locks.visibleItems(rows);
    final seen = <String>{};
    return visible
        .where(
          (item) =>
              item.type == widget.type &&
              !locks.titleConfigured(item) &&
              seen.add(item.id) &&
              (item.categoryId == null ||
                  !locks.configured(Category(item.categoryId!, '', item.type))),
        )
        .toList();
  }

  Future<List<ContentItem>> loadCategory(Category category) =>
      categoryData.putIfAbsent(category.id, () async {
        try {
          return await allowed(await widget.provider.getItems(category));
        } catch (_) {
          categoryData.remove(category.id);
          rethrow;
        }
      });
  Future<void> load() async {
    final version = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await locks.load();
      final available = (await widget.provider.getCategories(widget.type))
          .where(
            (c) =>
                !locks.hidden(c) &&
                !locks.configured(c) &&
                locks.allowsCategory(c),
          )
          .toList();
      final saved = await loadWatching();
      final listed = await allowed(await myList.items(widget.type));
      final recent = RecentCatalogCache.peek(widget.provider, widget.type);
      var initial = <ContentItem>[];
      if (recent != null) {
        try {
          initial = await allowed(await recent);
        } catch (_) {
          /* Fall back to category data. */
        }
      }
      if (initial.isEmpty) {
        for (final category in available) {
          initial = await loadCategory(category);
          if (initial.isNotEmpty) break;
        }
      }
      final rated =
          initial
              .where(
                (item) =>
                    item.rating != null &&
                    item.rating! >= 0 &&
                    item.rating! <= 10,
              )
              .toList()
            ..sort((a, b) => b.rating!.compareTo(a.rating!));
      final recentItems = recentlyAdded(initial);
      if (!mounted || version != generation) return;
      setState(() {
        categories = available;
        if (filter != null &&
            !available.any((category) => category.id == filter)) {
          filter = null;
          if (grid) gridItems = allItems();
        }
        watching = saved;
        savedTitles = listed;
        seed = initial;
        featured =
            saved.firstOrNull?.item ??
            rated.firstOrNull ??
            recentItems.firstOrNull ??
            initial.firstOrNull;
        loading = false;
      });
      if (focusOnReady) {
        focusOnReady = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) focusEntry();
        });
      }
    } catch (_) {
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          failed = true;
        });
      }
    }
  }

  Future<List<WatchEntry>> loadWatching() async {
    final entries =
        (await history.entries())
            .where((e) => e.item.type == widget.type)
            .toList()
          ..sort((a, b) => b.updated.compareTo(a.updated));
    final visible = await allowed(entries.map((e) => e.item).toList());
    final ids = visible.map((e) => e.id).toSet(), seen = <String>{};
    return entries
        .where((e) => ids.contains(e.item.id) && seen.add(e.item.id))
        .toList();
  }

  Future<void> historyChanged() async {
    final entries = await loadWatching();
    if (mounted) {
      setState(() {
        final wasWatching = watching.any(
          (entry) => entry.item.id == featured?.id,
        );
        watching = entries;
        if (entries.isNotEmpty &&
            !entries.any((entry) => entry.item.id == featured?.id)) {
          featured = entries.first.item;
        } else if (entries.isEmpty && wasWatching) {
          featured = seed.firstOrNull;
        }
      });
    }
  }

  Future<void> myListChanged() async {
    final revision = ++savedRevision;
    final titles = await allowed(await myList.items(widget.type));
    if (!mounted || revision != savedRevision) return;
    setState(() {
      savedTitles = titles;
      emptyRows.remove('my-list');
    });
  }

  void restrictionsChanged() {
    grid = false;
    gridItems = null;
    categoryData.clear();
    detailData.clear();
    emptyRows.clear();
    unawaited(load());
  }

  void focusEntry() {
    if (loading) {
      focusOnReady = true;
      return;
    }
    if (!grid && page.hasClients) {
      unawaited(
        page
            .animateTo(
              0,
              duration: const Duration(milliseconds: 210),
              curve: Curves.easeOut,
            )
            .then((_) async {
              await WidgetsBinding.instance.endOfFrame;
              if (!mounted) return;
              if (featured != null && detailsFocus.context != null) {
                detailsFocus.requestFocus();
              } else {
                searchFocus.requestFocus();
              }
            }),
      );
      return;
    }

    if (grid) {
      gridSearch.requestFocus();
    } else if (featured != null) {
      detailsFocus.requestFocus();
    } else {
      searchFocus.requestFocus();
    }
  }

  bool handleBack() {
    if (!grid) return false;
    setState(() {
      grid = false;
      filter = null;
      query = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusEntry();
    });
    return true;
  }

  Future<SeriesDetails> loadDetails(ContentItem item) =>
      detailData.putIfAbsent(item.id, () async {
        try {
          return movies
              ? SeriesDetails(
                  await widget.provider.getMovieDetails(item),
                  const [],
                )
              : await widget.provider.getSeriesDetails(item);
        } catch (_) {
          detailData.remove(item.id);
          rethrow;
        }
      });

  Future<void> open(
    ContentItem item, {
    WatchEntry? resume,
    bool watch = false,
  }) async {
    if (!await requestTitleAccess(context, widget.provider, item) || !mounted) {
      return;
    }
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => DetailsScreen(
          provider: widget.provider,
          item: item,
          autoPlay: watch,
          initialEpisode: resume?.episode,
          initialSeriesDetails: movies ? null : loadDetails(item),
          initialMovieDetails: movies
              ? loadDetails(item).then((value) => value.details)
              : null,
        ),
      ),
    );
    if (mounted) await historyChanged();
  }

  Future<List<ContentItem>> allItems() =>
      categoryData.putIfAbsent('__all__', () async {
        try {
          return await allowed(await widget.provider.getAllItems(widget.type));
        } catch (_) {
          categoryData.remove('__all__');
          rethrow;
        }
      });
  Future<void> search() async {
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => CatalogSearchScreen(
          provider: widget.provider,
          type: widget.type,
          initialCatalog: allItems(),
          onOpen: (item) => open(item),
        ),
      ),
    );
    if (mounted) searchFocus.requestFocus();
  }

  String get selectedCategoryName =>
      categories.where((c) => c.id == filter).firstOrNull?.name ??
      'All $catalogName';
  Future<void> chooseCategory() async {
    final result = await showCatalogCategoriesDrawer(
      context,
      categories: categories,
      allLabel: 'All $catalogName',
      selectedId: filter,
    );
    if (!mounted) return;
    if (result != null) showGrid(result.id, preserveQuery: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) categoriesFocus.requestFocus();
    });
  }

  void showGrid(String? categoryId, {bool preserveQuery = false}) {
    if (!preserveQuery) gridQueryController.clear();
    setState(() {
      grid = true;
      filter = categoryId;
      if (!preserveQuery) query = '';
      gridItems = categoryId == null
          ? allItems()
          : loadCategory(categories.firstWhere((c) => c.id == categoryId));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) gridSearch.requestFocus();
    });
  }

  List<_Section> get _sections {
    final rows = <_Section>[];
    if (watching.isNotEmpty) {
      rows.add(
        _Section(
          'continue',
          'Continue Watching',
          () async => watching.map((e) => e.item).toList(),
          landscape: true,
        ),
      );
    }
    if (savedTitles.isNotEmpty) {
      rows.add(_Section('my-list', 'My List', () async => savedTitles));
    }
    final recent = recentlyAdded(seed);
    if (recent.isNotEmpty) {
      rows.add(_Section('recent', 'Recently Added', () async => recent));
    }
    final rated =
        seed
            .where(
              (item) =>
                  item.rating != null &&
                  item.rating! >= 0 &&
                  item.rating! <= 10,
            )
            .toList()
          ..sort((a, b) => b.rating!.compareTo(a.rating!));
    if (rated.isNotEmpty) {
      final recentIds = recent.take(8).map((item) => item.id).toSet();
      final alternatives = rated
          .where((item) => !recentIds.contains(item.id))
          .toList();
      rows.add(
        _Section(
          'rated',
          'Top Rated',
          () async => (alternatives.isNotEmpty ? alternatives : rated)
              .take(20)
              .toList(),
        ),
      );
    }
    for (final category in categories) {
      rows.add(
        _Section(
          'category:${category.id}',
          category.name,
          () => loadCategory(category),
        ),
      );
    }
    return rows.where((r) => !emptyRows.contains(r.id)).toList();
  }

  Future<void> focusRow(int index, [int preferred = 0]) async {
    final rows = _sections;
    if (index < 0) {
      focusEntry();
      return;
    }
    if (index >= rows.length) {
      if (page.hasClients) {
        await page.animateTo(
          page.position.maxScrollExtent,
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOut,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) footerFocus.requestFocus();
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final key = _rowKey(rows[index].id);
    if (key.currentState == null && page.hasClients) {
      await page.animateTo(
        (56 +
                heroExtent +
                rows
                    .take(index)
                    .fold<double>(
                      0,
                      (sum, section) => sum + _extentFor(section),
                    ))
            .clamp(0, page.position.maxScrollExtent),
        duration: const Duration(milliseconds: 210),
        curve: Curves.easeOut,
      );
    }
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await key.currentState?.focus(preferred);
  }

  KeyEventResult headerKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      focusEntry();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        searchFocus.hasFocus) {
      widget.onNavigation();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget header() => SizedBox(
    height: 56,
    child: Row(
      children: [
        const Spacer(),
        Focus(
          canRequestFocus: false,
          onKeyEvent: (_, e) => headerKey(e),
          child: Row(
            children: [
              IconButton(
                focusNode: searchFocus,
                tooltip: 'Search $catalogLower',
                onPressed: search,
                icon: const Icon(Icons.search),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .3,
                ),
                child: TextButton.icon(
                  focusNode: categoriesFocus,
                  onPressed: chooseCategory,
                  icon: const Icon(Icons.filter_list, size: 20),
                  label: Text(
                    'Categories: $selectedCategoryName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => showGrid(null),
                child: Text('All $catalogName'),
              ),
              ...widget.headerActions,
              if (widget.headerActions.isEmpty)
                IconButton(
                  tooltip: 'Settings',
                  onPressed: widget.onSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 1920).clamp(.65, 1.1);
    final width = (180 * scale).clamp(130.0, 198.0);
    posterWidth = width;
    rowExtent = width * 1.5 + 130;
    heroExtent = (size.height * .42).clamp(250.0, 460.0);
    final rows = _sections;
    return ColoredBox(
      color: _background,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: loading
              ? SeriesCatalogSkeleton(label: 'Loading $catalogLower catalog')
              : failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Unable to load $catalogLower'),
                      TextButton(
                        autofocus: true,
                        onPressed: () {
                          categoryData.clear();
                          unawaited(load());
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : grid
              ? Column(
                  children: [
                    header(),
                    gridControls(),
                    Expanded(child: gridBody(width)),
                  ],
                )
              : featured == null
              ? Column(
                  children: [
                    header(),
                    Expanded(
                      child: Center(child: Text('No $catalogLower available')),
                    ),
                  ],
                )
              : ListView.builder(
                  key: PageStorageKey('${widget.type.name}-catalog-scroll'),
                  controller: page,
                  scrollCacheExtent: ScrollCacheExtent.pixels(rowExtent),
                  itemCount: rows.length + 3,
                  findChildIndexCallback: (key) {
                    if (key is ValueKey<String> &&
                        key.value.startsWith('series-section:')) {
                      final index = rows.indexWhere(
                        (row) => 'series-section:${row.id}' == key.value,
                      );
                      return index < 0 ? null : index + 2;
                    }
                    return null;
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) return header();
                    if (index == 1) {
                      return SizedBox(
                        height: heroExtent,
                        child: _FeaturedHero(
                          key: const ValueKey('series-featured-hero'),
                          item: featured!,
                          scale: scale,
                          details: loadDetails(featured!),
                          resume: watching
                              .where((e) => e.item.id == featured!.id)
                              .firstOrNull,
                          watchFocus: watchFocus,
                          detailsFocus: detailsFocus,
                          onWatch: () => open(
                            featured!,
                            watch: true,
                            resume: watching
                                .where((e) => e.item.id == featured!.id)
                                .firstOrNull,
                          ),
                          onDetails: () => open(featured!),
                          up: () => searchFocus.requestFocus(),
                          down: () => unawaited(focusRow(0)),
                          left: widget.onNavigation,
                        ),
                      );
                    }
                    if (index == rows.length + 2) {
                      return SizedBox(
                        height: 64,
                        child: Focus(
                          canRequestFocus: false,
                          onKeyEvent: (_, event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.arrowUp) {
                              unawaited(focusRow(rows.length - 1));
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextButton(
                            focusNode: footerFocus,
                            onPressed: () => showGrid(null),
                            child: Text('Browse All $catalogName'),
                          ),
                        ),
                      );
                    }
                    final row = index - 2, section = rows[row];
                    return SizedBox(
                      key: ValueKey('series-section:${section.id}'),
                      height: _extentFor(section),
                      child: _CatalogSection(
                        key: _rowKey(section.id),
                        section: section,
                        width: section.landscape ? width * 1.7 : width,
                        height: _extentFor(section),
                        provider: widget.provider,
                        watching: watching,
                        onOpen: (item) => open(item),
                        onResume: (entry) =>
                            open(entry.item, watch: true, resume: entry),
                        onMove: (direction, current) =>
                            unawaited(focusRow(row + direction, current)),
                        onNavigation: widget.onNavigation,
                        onEmpty: () {
                          if (mounted) {
                            setState(() => emptyRows.add(section.id));
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget gridControls() => Row(
    children: [
      Expanded(
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              gridSort.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: ActivationTextField(
            focusNode: gridSearch,
            controller: gridQueryController,
            onNavigateUp: () => searchFocus.requestFocus(),
            onNavigateDown: () => gridFirst.requestFocus(),
            decoration: InputDecoration(
              isDense: true,
              hintText: filter == null
                  ? 'Search all $catalogLower'
                  : 'Search $selectedCategoryName',
            ),
            onChanged: (value) => setState(() => query = value.toLowerCase()),
          ),
        ),
      ),
      Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            gridSearch.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            gridCatalog.requestFocus();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            gridFirst.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: PopupMenuButton<String>(
          key: gridSortMenu,
          tooltip: 'Sort $catalogLower',
          onSelected: (value) => setState(() => sort = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'provider', child: Text('Provider order')),
            PopupMenuItem(value: 'date', child: Text('Recently Added')),
            PopupMenuItem(value: 'az', child: Text('Title A-Z')),
            PopupMenuItem(value: 'za', child: Text('Title Z-A')),
            PopupMenuItem(
              value: 'year',
              child: Text('Release Year (when available)'),
            ),
            PopupMenuItem(
              value: 'rating',
              child: Text('Rating (when available)'),
            ),
          ],
          child: IconButton(
            focusNode: gridSort,
            icon: const Icon(Icons.sort),
            onPressed: () => gridSortMenu.currentState?.showButtonMenu(),
          ),
        ),
      ),
      Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            gridSort.requestFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            gridFirst.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextButton(
          focusNode: gridCatalog,
          onPressed: handleBack,
          child: const Text('Catalog'),
        ),
      ),
    ],
  );
  Widget gridBody(double width) => FutureBuilder<List<ContentItem>>(
    future: gridItems,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TextButton(
            onPressed: () {
              categoryData.remove(filter ?? '__all__');
              showGrid(filter);
            },
            child: const Text('Unable to load titles - Retry'),
          ),
        );
      }
      if (!snapshot.hasData) {
        return SeriesCatalogSkeleton(label: 'Loading $catalogLower catalog');
      }
      final rows = snapshot.data!
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
      switch (sort) {
        case 'az':
          rows.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        case 'za':
          rows.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
          );
        case 'date':
          rows.sort(
            (a, b) => (b.addedAt ?? DateTime(1970)).compareTo(
              a.addedAt ?? DateTime(1970),
            ),
          );
        case 'year':
          rows.sort(
            (a, b) => (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0),
          );
        case 'rating':
          rows.sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
      }
      if (rows.isEmpty) {
        return Center(child: Text('No $catalogLower available'));
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 850 ? 5 : 6;
          return GridView.builder(
            key: ValueKey((filter, query, sort)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: .56,
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
            ),
            itemCount: rows.length,
            itemBuilder: (_, index) => Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                    index % columns == 0) {
                  widget.onNavigation();
                  return KeyEventResult.handled;
                }
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp &&
                    index < columns) {
                  gridSearch.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: SeriesPosterCard(
                item: rows[index],
                provider: widget.provider,
                focusNode: index == 0 ? gridFirst : null,
                onOpen: () => open(rows[index]),
              ),
            ),
          );
        },
      );
    },
  );
}

class _Section {
  final String id, title;
  final Future<List<ContentItem>> Function() load;
  final bool landscape;
  const _Section(this.id, this.title, this.load, {this.landscape = false});
}

class _CatalogSection extends StatefulWidget {
  final _Section section;
  final double width, height;
  final IptvProvider provider;
  final List<WatchEntry> watching;
  final void Function(ContentItem) onOpen;
  final void Function(WatchEntry) onResume;
  final void Function(int, int) onMove;
  final VoidCallback onNavigation, onEmpty;
  const _CatalogSection({
    super.key,
    required this.section,
    required this.width,
    required this.height,
    required this.provider,
    required this.watching,
    required this.onOpen,
    required this.onResume,
    required this.onMove,
    required this.onNavigation,
    required this.onEmpty,
  });
  @override
  State<_CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<_CatalogSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => visited;
  late Future<List<ContentItem>> items = load();
  final rail = GlobalKey<MediaHorizontalRailState>();
  bool visited = false;
  Future<List<ContentItem>> load() async {
    final rows = await widget.section.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ArtworkPrefetch.images(context, rows.map((item) => item.artwork));
      }
    });
    if (rows.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onEmpty();
      });
    }
    return rows;
  }

  @override
  void didUpdateWidget(covariant _CatalogSection old) {
    super.didUpdateWidget(old);
    if (widget.section.landscape || widget.section.id == 'my-list') {
      items = widget.section.load();
    }
  }

  Future<void> focus(int preferred) async {
    await items;
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (visited) {
      rail.currentState?.focusCurrent();
    } else {
      visited = true;
      updateKeepAlive();
      await rail.currentState?.focusAt(preferred);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            widget.section.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ContentItem>>(
            future: items,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(() {
                    items = load();
                  }),
                  child: const Text('Unable to load titles - Retry'),
                );
              }
              if (!snapshot.hasData) {
                return const ColoredBox(color: Color(0xff151d28));
              }
              final rows = snapshot.data!;
              return MediaHorizontalRail(
                key: rail,
                count: rows.length,
                width: widget.width + 18,
                height: widget.height - 54,
                up: () => widget.onMove(-1, rail.currentState?.current ?? 0),
                down: () => widget.onMove(1, rail.currentState?.current ?? 0),
                onLeftBoundary: widget.onNavigation,
                itemBuilder: (index, node) {
                  final item = rows[index];
                  final entry = widget.watching
                      .where((e) => e.item.id == item.id)
                      .firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 14, 12),
                    child: SeriesPosterCard(
                      item: item,
                      provider: widget.provider,
                      focusNode: node,
                      progress: widget.section.landscape ? entry : null,
                      onOpen: () => widget.section.landscape && entry != null
                          ? widget.onResume(entry)
                          : widget.onOpen(item),
                      onDetails: () => widget.onOpen(item),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Shared poster treatment for catalog rows and the All Series grid.
class SeriesPosterCard extends StatelessWidget {
  final ContentItem item;
  final IptvProvider provider;
  final FocusNode? focusNode;
  final WatchEntry? progress;
  final VoidCallback onOpen;
  final VoidCallback? onDetails;
  const SeriesPosterCard({
    super.key,
    required this.item,
    required this.provider,
    this.focusNode,
    this.progress,
    required this.onOpen,
    this.onDetails,
  });
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.contextMenu &&
          onDetails != null) {
        onDetails!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TextButton(
      focusNode: focusNode,
      onPressed: onOpen,
      onLongPress: onDetails,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
      ),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedScale(
            scale: focused ? 1.04 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: focused ? const Color(0xff25364a) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? _blue : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: progress == null
                          ? CatalogPosterArtwork(item: item, provider: provider)
                          : ContinueWatchingArtwork(item: item),
                    ),
                  ),
                  if (progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: LinearProgressIndicator(
                        value: progress!.duration.inMilliseconds > 0
                            ? (progress!.position.inMilliseconds /
                                      progress!.duration.inMilliseconds)
                                  .clamp(0, 1)
                            : 0,
                        color: _blue,
                        backgroundColor: Colors.white24,
                        minHeight: 3,
                      ),
                    ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 38,
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (progress != null)
                    Text(
                      'Resume \u00b7 S${progress!.episode?.season ?? 1} E${progress!.episode?.number ?? 1} \u00b7 ${((progress!.duration - progress!.position).inSeconds / 60).ceil()} min left',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xffb4becc),
                      ),
                    )
                  else if (item.releaseYear != null)
                    Text(
                      '${item.releaseYear}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xffb4becc),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _FeaturedHero extends StatefulWidget {
  final ContentItem item;
  final Future<SeriesDetails> details;
  final WatchEntry? resume;
  final FocusNode watchFocus, detailsFocus;
  final VoidCallback onWatch, onDetails, up, down, left;
  final double scale;
  const _FeaturedHero({
    super.key,
    required this.item,
    required this.details,
    required this.resume,
    required this.watchFocus,
    required this.detailsFocus,
    required this.onWatch,
    required this.onDetails,
    required this.up,
    required this.down,
    required this.left,
    required this.scale,
  });
  @override
  State<_FeaturedHero> createState() => _FeaturedHeroState();
}

class _FeaturedHeroState extends State<_FeaturedHero> {
  late Future<(Uri?, Uri?)> artwork = loadArtwork();
  @override
  void didUpdateWidget(covariant _FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) artwork = loadArtwork();
  }

  Future<(Uri?, Uri?)> loadArtwork() async {
    try {
      final info = (await widget.details).details;
      final service = TmdbArtworkService.configured;
      final result = await Future.wait([
        service.titleLogo(info),
        info.backdrop == null
            ? service.detailsBackdrop(info)
            : Future.value(info.backdrop),
      ]);
      return (result[0], result[1]);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<SeriesDetails>(
        future: widget.details,
        builder: (context, snapshot) {
          final info = snapshot.data?.details;
          return FutureBuilder<(Uri?, Uri?)>(
            future: artwork,
            builder: (context, images) {
              final backdrop = images.data?.$2 ?? info?.backdrop;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0xff151d28)),
                  if (backdrop != null)
                    CachedNetworkImage(
                      imageUrl: backdrop.toString(),
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      memCacheWidth: 1280,
                      errorWidget: (_, _, _) => const SizedBox(),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xff0b1018),
                          Color(0xdd0b1018),
                          Color(0x220b1018),
                        ],
                        stops: [0, .4, 1],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: MediaQuery.sizeOf(context).width * .48,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (images.data?.$1 != null)
                                CachedNetworkImage(
                                  imageUrl: images.data!.$1.toString(),
                                  height: 54 * widget.scale,
                                  width: 300 * widget.scale,
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.contain,
                                  errorWidget: (_, _, _) => Text(
                                    widget.item.type == ContentType.movies
                                        ? widget.item.name
                                        : TmdbCastService.cleanSeriesTitle(
                                            widget.item.name,
                                          ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 34 * widget.scale,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  widget.item.type == ContentType.movies
                                      ? widget.item.name
                                      : TmdbCastService.cleanSeriesTitle(
                                          widget.item.name,
                                        ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 34 * widget.scale,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (info != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    [
                                      TmdbCastService.configured.year(info) ??
                                          '',
                                      info.genre,
                                      if (snapshot.data!.episodes.isNotEmpty)
                                        '${snapshot.data!.episodes.map((e) => e.season).toSet().length} Seasons',
                                      if (info.rating.isNotEmpty)
                                        '\u2605 ${double.tryParse(info.rating)?.toStringAsFixed(1) ?? info.rating}',
                                    ].where((s) => s.isNotEmpty).join(' \u00b7 '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16 * widget.scale,
                                      color: const Color(0xffb4becc),
                                    ),
                                  ),
                                ),
                              if (info != null && info.synopsis.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    info.synopsis,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 19 * widget.scale,
                                      height: 1.3,
                                      color: const Color(0xffb4becc),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Focus(
                          canRequestFocus: false,
                          onKeyEvent: (_, event) {
                            if (event is! KeyDownEvent &&
                                event is! KeyRepeatEvent) {
                              return KeyEventResult.ignored;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              widget.down();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              widget.up();
                              return KeyEventResult.handled;
                            }
                            if (event.logicalKey ==
                                    LogicalKeyboardKey.arrowLeft &&
                                widget.watchFocus.hasFocus) {
                              widget.left();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: Row(
                            children: [
                              FilledButton.icon(
                                focusNode: widget.watchFocus,
                                onPressed: widget.onWatch,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xff10151c),
                                  minimumSize: const Size(0, 38),
                                ),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(
                                  widget.resume == null
                                      ? 'Watch Now'
                                      : widget.resume!.episode == null
                                      ? 'Resume'
                                      : 'Resume S${widget.resume!.episode!.season} E${widget.resume!.episode!.number}',
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                focusNode: widget.detailsFocus,
                                onPressed: widget.onDetails,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: const Color(0xcc202a36),
                                  minimumSize: const Size(0, 38),
                                  side: const BorderSide(color: _blue),
                                ),
                                child: const Text('Details'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class SeriesCatalogSkeleton extends StatelessWidget {
  final String label;
  const SeriesCatalogSkeleton({
    super.key,
    this.label = 'Loading series catalog',
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 56),
        Container(height: 200, color: const Color(0xff151d28)),
        const SizedBox(height: 20),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 6,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (_, _) =>
                Container(width: 130, color: const Color(0xff202a36)),
          ),
        ),
      ],
    ),
  );
}
