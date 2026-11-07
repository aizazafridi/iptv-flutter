import 'poster_focus_preview.dart';
import 'artwork_retry.dart';
import '../data/locked_provider.dart';
import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
import 'history_removal.dart';
import '../application/browsing_mode.dart';
import 'lite_media_list.dart';
import 'catalog_categories_drawer.dart';
import 'dart:async';
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
  final posterPreview = PosterPreviewController();
  final page = ScrollController();
  final gridScroll = ScrollController();
  final gridSelected = FocusNode(debugLabel: 'catalog restored title');
  bool restoreGridSelection = false, restoreLiteSelection = false;
  String? restoredGridTitle;
  final gridQueryController = TextEditingController();
  final categoriesFocus = FocusNode(debugLabel: 'catalog categories');
  final searchFocus = FocusNode(debugLabel: 'series catalog search');
  final detailsFocus = FocusNode(debugLabel: 'series featured details');
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
  Timer? featuredFocusTimer;

  void focusTitle(ContentItem item) {
    selectedTitle = item.id;
    if (BrowsingModeSettings.instance.lite) return;
    featuredFocusTimer?.cancel();
    featuredFocusTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && selectedTitle == item.id && featured?.id != item.id) {
        setState(() => featured = item);
      }
    });
  }

  bool loading = true, failed = false, grid = false;
  String? filter;
  String liteSection = 'all';
  String? selectedTitle;
  Timer? liteSearchDelay;
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
    ArtworkMetrics.record('catalog_open', values: {'type': widget.type.name});
    BrowsingModeSettings.instance.addListener(modeChanged);
    history.addListener(historyChanged);
    myList.addListener(myListChanged);
    locks.addListener(restrictionsChanged);
    unawaited(load());
    startFeaturedRotation();
  }

  void startFeaturedRotation() {
    featuredTimer?.cancel();
    if (BrowsingModeSettings.instance.lite) return;
    featuredTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted ||
          loading ||
          (selectedTitle != null) ||
          BrowsingModeSettings.instance.lite ||
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
    featuredFocusTimer?.cancel();
    posterPreview.dispose();
    liteSearchDelay?.cancel();
    BrowsingModeSettings.instance.removeListener(modeChanged);
    featuredTimer?.cancel();
    history.removeListener(historyChanged);
    myList.removeListener(myListChanged);
    locks.removeListener(restrictionsChanged);
    page.dispose();
    gridScroll.dispose();
    gridQueryController.dispose();
    for (final node in [
      categoriesFocus,
      searchFocus,
      detailsFocus,
      gridSearch,
      gridSort,
      gridCatalog,
      gridFirst,
      gridSelected,
      footerFocus,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<List<ContentItem>> allowed(List<ContentItem> rows) async {
    final provider = widget.provider;
    final visible = provider is LockedProvider
        ? await provider.visibleSavedItems(rows, excludeConfiguredLocks: true)
        : await locks.visibleItems(rows, excludeConfiguredLocks: true);
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
    final clock = Stopwatch()..start();
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
      if (initial.isEmpty && BrowsingModeSettings.instance.lite) {
        initial = await allItems();
      }
      if (initial.isEmpty && !BrowsingModeSettings.instance.lite) {
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
      ArtworkMetrics.record(
        'catalog_metadata_ready',
        values: {
          'type': widget.type.name,
          'elapsed_ms': clock.elapsedMilliseconds,
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ArtworkMetrics.record(
            'catalog_usable_frame',
            values: {
              'type': widget.type.name,
              'elapsed_ms': clock.elapsedMilliseconds,
            },
          );
        }
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

  void modeChanged() {
    if (!mounted) return;
    posterPreview.dismiss(restoreFocus: false);
    startFeaturedRotation();
    restoreLiteSelection = BrowsingModeSettings.instance.lite;
    if (!BrowsingModeSettings.instance.lite && selectedTitle != null) {
      grid = true;
      gridItems = filter == null
          ? allItems()
          : loadCategory(categories.firstWhere((c) => c.id == filter));
      restoredGridTitle = selectedTitle;
      restoreGridSelection = true;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) focusEntry();
    });
  }

  void focusEntry() {
    if (BrowsingModeSettings.instance.lite) {
      gridSearch.requestFocus();
      return;
    }
    if (loading) {
      focusOnReady = true;
      return;
    }
    if (!grid && page.hasClients) {
      unawaited(
        page
            .animateTo(
              0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
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
    if (grid && posterPreview.dismiss()) return true;
    if (!grid) {
      posterPreview.close();
      return false;
    }
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
    posterPreview.dismiss(restoreFocus: false);
    selectedTitle = item.id;
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
          return await allowed(
            await RecentCatalogCache.loadAll(widget.provider, widget.type),
          );
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
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
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
        rows
            .take(index)
            .fold<double>(0, (sum, section) => sum + _extentFor(section))
            .clamp(0, page.position.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
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
    if (BrowsingModeSettings.instance.lite) return liteCatalog();
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 1920).clamp(.65, 1.1);
    final width = (180 * scale).clamp(122.0, 198.0);
    posterWidth = width;
    rowExtent = width * 1.3 + 108;
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
                    if (featured != null) featuredPanel(scale),
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
              : catalogRows(
                  ListView.builder(
                    key: PageStorageKey('${widget.type.name}-catalog-scroll'),
                    controller: page,
                    scrollCacheExtent: ScrollCacheExtent.pixels(rowExtent),
                    itemCount: rows.length + 1,
                    findChildIndexCallback: (key) {
                      if (key is ValueKey<String> &&
                          key.value.startsWith('series-section:')) {
                        final index = rows.indexWhere(
                          (row) => 'series-section:${row.id}' == key.value,
                        );
                        return index < 0 ? null : index;
                      }
                      return null;
                    },
                    itemBuilder: (context, index) {
                      index += 2;
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
                          onFocus: focusTitle,
                          onResume: (entry) =>
                              open(entry.item, watch: true, resume: entry),
                          onMove: (direction, current) =>
                              unawaited(focusRow(row + direction)),
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
                  scale,
                ),
        ),
      ),
    );
  }

  Widget featuredPanel(double scale) {
    return SizedBox(
      height: heroExtent,
      child: _FeaturedHero(
        key: const ValueKey('series-featured-hero'),
        item: featured!,
        scale: scale,
        details: loadDetails(featured!),
        detailsFocus: detailsFocus,
        onDetails: () => open(featured!),
        up: () => searchFocus.requestFocus(),
        down: () => grid ? gridSearch.requestFocus() : unawaited(focusRow(0)),
        left: widget.onNavigation,
      ),
    );
  }

  Widget catalogRows(Widget rows, double scale) => Column(
    children: [
      header(),
      featuredPanel(scale),
      Expanded(child: rows),
    ],
  );

  Widget liteCatalog() => ColoredBox(
    color: const Color(0xff0d121b),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$catalogName \u00b7 LITE',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
          gridControls(),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                focusNode: categoriesFocus,
                onPressed: chooseCategory,
                icon: const Icon(Icons.filter_list, size: 18),
                label: Text('Categories: $selectedCategoryName'),
              ),
              for (final entry in {
                'all': 'All $catalogName',
                'continue': 'Continue Watching',
                'list': 'My List',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: liteSection == entry.key,
                  onSelected: (_) => setState(() => liteSection = entry.key),
                ),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<ContentItem>>(
              future: filter == null
                  ? allItems()
                  : loadCategory(categories.firstWhere((c) => c.id == filter)),
              builder: (context, snapshot) {
                if (snapshot.hasError || failed) {
                  return Center(
                    child: TextButton(
                      onPressed: () {
                        RecentCatalogCache.invalidate(widget.provider);
                        categoryData.clear();
                        unawaited(load());
                        setState(() {});
                      },
                      child: Text('Unable to load $catalogLower. Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                var items = snapshot.data!;
                final source = liteSection == 'continue'
                    ? watching.map((e) => e.item).toList()
                    : liteSection == 'list'
                    ? savedTitles
                    : items;
                final allowedIds = items.map((item) => item.id).toSet();
                final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
                items = source
                    .where(
                      (item) =>
                          allowedIds.contains(item.id) &&
                          terms.every(item.name.toLowerCase().contains),
                    )
                    .toList();
                switch (sort) {
                  case 'az':
                    items.sort(
                      (a, b) =>
                          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                    );
                  case 'za':
                    items.sort(
                      (a, b) =>
                          b.name.toLowerCase().compareTo(a.name.toLowerCase()),
                    );
                  case 'date':
                    items.sort(
                      (a, b) => (b.addedAt ?? DateTime(1970)).compareTo(
                        a.addedAt ?? DateTime(1970),
                      ),
                    );
                  case 'year':
                    items.sort(
                      (a, b) =>
                          (b.releaseYear ?? 0).compareTo(a.releaseYear ?? 0),
                    );
                  case 'rating':
                    items.sort(
                      (a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1),
                    );
                }
                if (items.isEmpty) {
                  return const Center(child: Text('No matching titles.'));
                }
                final restore = restoreLiteSelection;
                restoreLiteSelection = false;
                return LiteMediaList(
                  onRemove: liteSection == 'continue'
                      ? (item) => confirmHistoryRemoval(context, history, item)
                      : null,
                  restoreFocus: restore,
                  key: ValueKey((filter, query, sort, liteSection)),
                  items: items,
                  selectedId: selectedTitle,
                  entryFocus: gridFirst,
                  up: gridSearch.requestFocus,
                  left: widget.onNavigation,
                  onFocus: (id) => selectedTitle = id,
                  onOpen: (item) => open(
                    item,
                    watch: liteSection == 'continue',
                    resume: watching
                        .where((e) => e.item.id == item.id)
                        .firstOrNull,
                  ),
                  subtitle: (item) {
                    final entry = watching
                        .where((e) => e.item.id == item.id)
                        .firstOrNull;
                    return entry == null
                        ? item.releaseYear?.toString() ?? ''
                        : '${entry.item.type != ContentType.series || entry.episode == null ? '' : 'S${entry.episode!.season} E${entry.episode!.number} \u00b7 '}${((entry.duration - entry.position).inSeconds / 60).ceil().clamp(0, 99999)} min left';
                  },
                  progress: (item) {
                    final entry = watching
                        .where((e) => e.item.id == item.id)
                        .firstOrNull;
                    return entry == null || entry.duration <= Duration.zero
                        ? null
                        : entry.position.inMilliseconds /
                              entry.duration.inMilliseconds;
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

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
            onChanged: (value) {
              if (!BrowsingModeSettings.instance.lite) {
                setState(() => query = value.toLowerCase());
                return;
              }
              liteSearchDelay?.cancel();
              liteSearchDelay = Timer(const Duration(milliseconds: 200), () {
                if (mounted) setState(() => query = value.toLowerCase());
              });
            },
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
          onPressed: BrowsingModeSettings.instance.lite
              ? widget.onNavigation
              : handleBack,
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
        return Center(child: Text('Loading $catalogLower catalog'));
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
          final columns = constraints.maxWidth < 850 ? 6 : 7;
          final selectedIndex = rows.indexWhere(
            (item) => item.id == restoredGridTitle,
          );
          if (restoreGridSelection && selectedIndex >= 0) {
            restoreGridSelection = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !gridScroll.hasClients) return;
              final tileWidth =
                  (constraints.maxWidth - 12 - (columns - 1) * 18) / columns;
              gridScroll.jumpTo(
                ((selectedIndex ~/ columns) * (tileWidth / .63 + 18)).clamp(
                  0,
                  gridScroll.position.maxScrollExtent,
                ),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && ModalRoute.of(context)?.isCurrent == true) {
                  (selectedIndex == 0 ? gridFirst : gridSelected)
                      .requestFocus();
                }
              });
              WidgetsBinding.instance.scheduleFrame();
            });
          }

          return GridView.builder(
            controller: gridScroll,
            key: ValueKey((filter, query, sort)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: .63,
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
                focusNode: index == 0
                    ? gridFirst
                    : index == selectedIndex
                    ? gridSelected
                    : null,
                inlineExpansion: false,
                onFocus: () => focusTitle(rows[index]),
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
  final ValueChanged<ContentItem>? onFocus;
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
    this.onFocus,
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
      if (mounted) {}
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
    if (!visited) {
      visited = true;
      updateKeepAlive();
    }
    await rail.currentState?.focusAt(preferred);
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
                  Widget card(FocusNode focus) => SeriesPosterCard(
                    item: item,
                    provider: widget.provider,
                    focusNode: focus,
                    inlineExpansion: false,
                    onFocus: () => widget.onFocus?.call(item),
                    progress: widget.section.landscape ? entry : null,
                    onOpen: () => widget.section.landscape && entry != null
                        ? widget.onResume(entry)
                        : widget.onOpen(item),
                    onRemove: widget.section.landscape
                        ? () => confirmHistoryRemoval(
                            context,
                            WatchHistory.forProvider(widget.provider),
                            item,
                          )
                        : null,
                    onDetails: () => widget.onOpen(item),
                  );
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 14, 12),
                    child: card(node),
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
  final bool inlineExpansion;
  final FocusNode? focusNode;
  final WatchEntry? progress;
  final VoidCallback onOpen;
  final VoidCallback? onDetails, onFocus, onRemove;
  const SeriesPosterCard({
    this.inlineExpansion = true,
    super.key,
    required this.item,
    required this.provider,
    this.focusNode,
    this.progress,
    required this.onOpen,
    this.onDetails,
    this.onRemove,
    this.onFocus,
  });
  @override
  Widget build(BuildContext context) => onRemove == null
      ? card(context)
      : HistoryRemoteAction(
          onOpen: onOpen,
          onRemove: onRemove!,
          child: card(context),
        );
  Widget card(BuildContext context) => Focus(
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
      onFocusChange: (focused) {
        if (focused) onFocus?.call();
      },
      onPressed: onOpen,
      onLongPress: onRemove ?? onDetails,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final focused = Focus.of(context).hasFocus;
          final movie = item.type == ContentType.movies;
          final expansion = movie ? 1.28 : 1.22;
          return TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 1,
              end: focused && inlineExpansion ? expansion : 1,
            ),
            builder: (_, factor, child) => OverflowBox(
              minWidth: 0,
              maxWidth: double.infinity,
              child: SizedBox(
                width:
                    constraints.maxWidth /
                    (inlineExpansion ? expansion : 1) *
                    factor,
                height: constraints.maxHeight,
                child: child,
              ),
            ),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
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
                  if (movie && inlineExpansion)
                    SizedBox(
                      height: 34,
                      child: focused
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    if (item.releaseYear != null)
                                      '${item.releaseYear}',
                                    if (item.rating != null)
                                      '\u2605 ${item.rating!.toStringAsFixed(1)}/10',
                                    'Movie',
                                  ].join(' \u00b7 '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffb4becc),
                                  ),
                                ),
                                if (progress != null)
                                  Text(
                                    'Resume - ${((progress!.duration - progress!.position).inSeconds / 60).ceil()} min left',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xffb4becc),
                                    ),
                                  ),
                              ],
                            )
                          : progress != null
                          ? Text(
                              'Resume - ${((progress!.duration - progress!.position).inSeconds / 60).ceil()} min left',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xffb4becc),
                              ),
                            )
                          : null,
                    )
                  else if (progress != null)
                    Text(
                      'Resume \u00b7 ${item.type == ContentType.series && progress!.episode != null ? 'S${progress!.episode!.season} E${progress!.episode!.number} \u00b7 ' : ''}${((progress!.duration - progress!.position).inSeconds / 60).ceil()} min left',
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
  final FocusNode detailsFocus;
  final VoidCallback onDetails, up, down, left;
  final double scale;
  const _FeaturedHero({
    super.key,
    required this.item,
    required this.details,
    required this.detailsFocus,
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
  Uri? arrivingLogo, arrivingBackdrop;
  Future<Uri?>? brokenBackdrop;
  ArtworkRetryScope artworkRetries = ArtworkRetryScope();
  @override
  void dispose() {
    artworkRetries.dispose();
    super.dispose();
  }

  late Future<(Uri?, Uri?)> artwork = loadArtwork();
  @override
  void didUpdateWidget(covariant _FeaturedHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      artworkRetries.dispose();
      artworkRetries = ArtworkRetryScope();
      brokenBackdrop = null;
      arrivingLogo = null;
      arrivingBackdrop = null;
      artwork = loadArtwork();
    }
  }

  Widget recoverBackdrop(MediaDetails? info) {
    if (info == null) return const SizedBox();
    return FutureBuilder<Uri?>(
      future: brokenBackdrop ??= retryArtwork<Uri?>(
        scope: artworkRetries,
        load: () => TmdbArtworkService.configured.detailsBackdrop(info),
        usable: (value) => value != null,
        active: () => mounted && widget.item.id == info.item.id,
      ),
      builder: (context, snapshot) => snapshot.data == null
          ? const SizedBox()
          : SharedArtworkImage(
              kind: ArtworkKind.backdrop,
              imageUrl: snapshot.data.toString(),
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
    );
  }

  Future<(Uri?, Uri?)> loadArtwork() async {
    try {
      final info = (await widget.details).details;
      final service = TmdbArtworkService.configured;
      final result = await Future.wait([
        retryArtwork<Uri?>(
          scope: artworkRetries,
          load: () => service.titleLogo(info),
          usable: (value) => value != null,
          active: () => mounted && widget.item.id == info.item.id,
        ).then((uri) {
          if (mounted && widget.item.id == info.item.id) {
            setState(() => arrivingLogo = uri);
          }
          return uri;
        }),
        (info.backdrop == null
                ? retryArtwork<Uri?>(
                    scope: artworkRetries,
                    load: () => service.detailsBackdrop(info),
                    usable: (value) => value != null,
                    active: () => mounted && widget.item.id == info.item.id,
                  )
                : Future.value(info.backdrop))
            .then((uri) {
              if (mounted && widget.item.id == info.item.id) {
                setState(() => arrivingBackdrop = uri);
              }
              return uri;
            }),
      ]);
      return (result[0], result[1]);
    } catch (_) {
      return (null, null);
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.detailsFocus,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.down();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.up();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        widget.left();
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          [
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.select,
          ].contains(event.logicalKey)) {
        widget.onDetails();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<SeriesDetails>(
          key: ValueKey(widget.item.id),
          future: widget.details,
          builder: (context, snapshot) {
            final info = snapshot.data?.details;
            return FutureBuilder<(Uri?, Uri?)>(
              future: artwork,
              builder: (context, images) {
                final backdrop =
                    images.data?.$2 ?? arrivingBackdrop ?? info?.backdrop;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xff151d28)),
                    if (backdrop != null)
                      SharedArtworkImage(
                        kind: ArtworkKind.backdrop,
                        imageUrl: backdrop.toString(),
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorWidget: (_, _, _) => recoverBackdrop(info),
                      ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xdd0b1018),
                            Color(0x660b1018),
                            Color(0x000b1018),
                            Color(0x000b1018),
                          ],
                          stops: [0, .32, .62, 1],
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
                                if ((images.data?.$1 ?? arrivingLogo) != null)
                                  SharedArtworkImage(
                                    imageUrl: (images.data?.$1 ?? arrivingLogo)
                                        .toString(),
                                    kind: ArtworkKind.logo,
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
