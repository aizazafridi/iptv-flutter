import 'continue_watching_artwork.dart';
import 'series_catalog_screen.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'live_tv_launch_screen.dart';
import 'on_now_panel.dart';
import 'weather_panel.dart';
import '../data/last_live_channel.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../application/session.dart';
import '../application/appearance.dart';
import '../application/watch_history.dart';
import '../application/my_list.dart';
import '../application/category_locks.dart';
import '../data/locked_provider.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'browse_screen.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'recordings_library_screen.dart';
import 'lock_password_dialog.dart';
import 'title_access.dart';
import 'search_screen.dart';
import 'smooth_page_route.dart';

const _accent = Color(0xff64b5f6);

class StreamoraDashboard extends StatefulWidget {
  final Session session;
  final AppAppearance appearance;
  final VoidCallback onSettings;
  final List<Widget> headerActions;
  const StreamoraDashboard({
    super.key,
    required this.session,
    required this.appearance,
    required this.onSettings,
    this.headerActions = const [],
  });
  @override
  State<StreamoraDashboard> createState() => _StreamoraDashboardState();
}

class _StreamoraDashboardState extends State<StreamoraDashboard>
    with SingleTickerProviderStateMixin {
  late final seriesFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  IptvProvider get provider => widget.session.provider!;
  late final history = WatchHistory.forProvider(provider);
  late final parental = CategoryLocks.forProvider(provider);
  late Future<List<WatchEntry>> watching = loadHistory();
  late Future<List<ContentItem>> live = loadLive();
  ContentItem? featured;
  List<EpgProgramme> programmes = [];
  final guides = <String, Future<List<EpgProgramme>>>{};
  Future<List<EpgProgramme>> channelGuide(ContentItem item) =>
      guides.putIfAbsent(item.id, () async {
        final p = provider;
        return p is EpgProvider
            ? (p as EpgProvider).getEpg(item)
            : <EpgProgramme>[];
      });
  Timer? refresh;
  int guideVersion = 0;
  bool loadingGuide = false;
  bool collapsed = false;
  DateTime? exitPressed;
  bool seriesActive = false, seriesCreated = false;
  bool moviesActive = false, moviesCreated = false;
  final movieCatalog = GlobalKey<SeriesCatalogScreenState>();
  SeriesCatalogScreenState? get activeCatalog =>
      moviesActive ? movieCatalog.currentState : seriesCatalog.currentState;
  void openMovies() {
    seriesFade.forward(from: 0);
    setState(() {
      moviesActive = true;
      moviesCreated = true;
      seriesActive = false;
      collapsed = true;
      lastNav = 'Movies';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) movieCatalog.currentState?.focusEntry();
    });
  }

  final seriesCatalog = GlobalKey<SeriesCatalogScreenState>();
  void openSeries() {
    seriesFade.forward(from: 0);
    setState(() {
      seriesActive = true;
      moviesActive = false;
      seriesCreated = true;
      collapsed = true;
      lastNav = 'Series';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) seriesCatalog.currentState?.focusEntry();
    });
  }

  void openHome() {
    setState(() {
      seriesActive = false;
      moviesActive = false;
      collapsed = false;
    });
    navNode('Home').requestFocus();
  }

  final contentScroll = ScrollController();
  final navNodes = <String, FocusNode>{};
  final railFocus = FocusNode(debugLabel: 'dashboard sidebar');
  final contentFocus = FocusNode(debugLabel: 'dashboard content');
  void syncSidebar() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (!railFocus.hasFocus && !contentFocus.hasFocus) return;
    final next = !railFocus.hasFocus;
    if (collapsed != next) setState(() => collapsed = next);
  }

  final liveFocus = FocusNode(debugLabel: 'dashboard Live TV');
  final onNowFocus = FocusNode(debugLabel: 'dashboard On Now');
  final searchFocus = FocusNode(debugLabel: 'dashboard Search');
  final headerNodes = <int, FocusNode>{};
  FocusNode headerNode(int index) => headerNodes.putIfAbsent(
    index,
    () => FocusNode(debugLabel: 'dashboard header $index'),
  );
  List<int> get headerIndices => [
    for (var i = 0; i < widget.headerActions.length; i++)
      if (widget.headerActions[i] is IconButton ||
          widget.headerActions[i] is PopupMenuButton<String>)
        i,
  ];
  void focusHeader(int index) {
    final node = headerNode(index);
    final target = node.descendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .firstOrNull;
    (target ?? node).requestFocus();
  }

  Widget headerAction(int index) => Focus(
    focusNode: headerNode(index),
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final position = headerIndices.indexOf(index);
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (position > 0) {
          focusHeader(headerIndices[position - 1]);
        } else {
          searchFocus.requestFocus();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (position + 1 < headerIndices.length) {
          focusHeader(headerIndices[position + 1]);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (provider.supportedTypes.contains(ContentType.live)) {
          onNowFocus.requestFocus();
        } else {
          returnToNavigation();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: widget.headerActions[index],
  );
  String lastNav = 'Home';
  List<String> get navigation => [
    'Home',
    if (provider.supportedTypes.contains(ContentType.live)) 'Live TV',
    if (provider.supportedTypes.contains(ContentType.movies)) 'Movies',
    if (provider.supportedTypes.contains(ContentType.series)) 'Series',
    if (provider.supportedTypes.contains(ContentType.live)) 'TV Guide',
  ];
  FocusNode navNode(String title) => navNodes.putIfAbsent(
    title,
    () => FocusNode(debugLabel: 'dashboard nav $title'),
  );
  void returnToNavigation() => navNode(lastNav).requestFocus();
  KeyEventResult navigationKey(String title, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final index = navigation.indexOf(title);
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
          ? 1
          : -1;
      final next = (index + direction).clamp(0, navigation.length - 1);
      navNode(navigation[next]).requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (seriesActive || moviesActive) {
        activeCatalog?.focusEntry();
      } else if (provider.supportedTypes.contains(ContentType.live)) {
        liveFocus.requestFocus();
      } else {
        searchFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navNode('Home').requestFocus();
    });
    FocusManager.instance.addListener(syncSidebar);
    history.addListener(historyChanged);
    parental.addListener(historyChanged);
    unawaited(
      live.then<void>((_) {}, onError: (Object error, StackTrace stack) {}),
    );
    refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      guides.clear();
      if (featured != null) unawaited(selectFeature(featured!));
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(syncSidebar);
    railFocus.dispose();
    contentFocus.dispose();
    for (final node in navNodes.values) {
      node.dispose();
    }
    for (final node in headerNodes.values) {
      node.dispose();
    }
    liveFocus.dispose();
    onNowFocus.dispose();
    searchFocus.dispose();
    contentScroll.dispose();
    refresh?.cancel();
    seriesFade.dispose();
    history.removeListener(historyChanged);
    parental.removeListener(historyChanged);
    super.dispose();
  }

  void historyChanged() {
    if (mounted) {
      setState(() {
        watching = loadHistory();
      });
    }
  }

  Future<List<ContentItem>> visible(List<ContentItem> rows) async {
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    if (provider is LockedProvider) {
      return (provider as LockedProvider).visibleSavedItems(rows);
    }
    return locks.visibleItems(rows);
  }

  Future<List<WatchEntry>> loadHistory() async {
    final entries = (await history.entries()).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    final allowed = await visible(entries.map((e) => e.item).toList());
    await parental.load();
    allowed.removeWhere(
      (item) =>
          parental.titleConfigured(item) ||
          parental.titleHidden(item) ||
          (item.categoryId != null &&
              (parental.configured(Category(item.categoryId!, '', item.type)) ||
                  parental.hidden(Category(item.categoryId!, '', item.type)))),
    );
    final seenSeries = <String>{};
    return entries
        .where(
          (entry) =>
              entry.item.type != ContentType.series ||
              seenSeries.add(entry.item.id),
        )
        .where(
          (e) => allowed.any((i) => i.id == e.item.id && i.type == e.item.type),
        )
        .take(12)
        .toList();
  }

  Future<List<ContentItem>> loadLive() async {
    if (!provider.supportedTypes.contains(ContentType.live)) return [];
    var rows = await visible(
      await MyList.forProvider(provider).items(ContentType.live),
    );
    if (rows.isEmpty) {
      final last = await LastLiveChannel.forProvider(provider).load();
      if (last != null) rows = await visible([last]);
    }
    rows = rows.take(6).toList();
    if (mounted && rows.isNotEmpty) unawaited(selectFeature(rows.first));
    return rows;
  }

  Future<void> selectFeature(ContentItem item) async {
    final version = ++guideVersion;
    setState(() {
      featured = item;
      programmes = [];
      loadingGuide = true;
    });
    try {
      final guide = await channelGuide(item);
      if (mounted && version == guideVersion) {
        setState(() => programmes = guide);
      }
    } catch (_) {
      /* The channel remains available when its guide is missing. */
    } finally {
      if (mounted && version == guideVersion) {
        setState(() => loadingGuide = false);
      }
    }
  }

  Future<void> push(Widget screen) async {
    await Navigator.of(
      context,
    ).push(SmoothPageRoute<void>(builder: (_) => screen));
    if (mounted) {
      historyChanged();
      setState(() {
        live = loadLive();
      });
    }
  }

  void browse(ContentType type) => push(
    type == ContentType.live
        ? LiveTvLaunchScreen(provider: provider)
        : BrowseScreen(
            provider: provider,
            type: type,
            appearance: widget.appearance,
          ),
  );
  Future<void> openItem(ContentItem item) async {
    if (!await requestTitleAccess(context, provider, item) || !mounted) return;
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    if (!mounted) return;
    if (item.categoryId != null) {
      final category = Category(item.categoryId!, '', item.type);
      if (locks.isLocked(category)) {
        final pin = await showDialog<String>(
          context: context,
          builder: (_) => LockPasswordDialog(locks: locks),
        );
        if (!mounted || pin == null || !locks.unlock(category, pin)) return;
      }
    }
    if (item.type != ContentType.live) {
      await push(DetailsScreen(provider: provider, item: item));
      return;
    }
    try {
      final source = await provider.resolvePlayback(item);
      if (!mounted) return;
      final p = provider;
      await push(
        PlayerScreen(
          source: source,
          liveTvMode: true,
          item: item,
          provider: provider,
          loadChannels: () => item.categoryId == null
              ? provider.getAllItems(ContentType.live)
              : provider.getItems(
                  Category(item.categoryId!, '', ContentType.live),
                ),
          resolveChannel: provider.resolvePlayback,
          channelEpg: p is EpgProvider ? (p as EpgProvider).getEpg : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this channel. Please retry.'),
          ),
        );
      }
    }
  }

  Future<ContentType?> chooseType(String title) => showDialog<ContentType>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(title),
      children: [
        for (final type in provider.supportedTypes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, type),
            child: Text(type.label),
          ),
      ],
    ),
  );
  Future<void> recordings() async {
    final type = await chooseType('Recordings');
    if (type == null || !mounted) return;
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    final category = CategoryLocks.recordingsCategory(type);
    if (!mounted) return;
    if (locks.hidden(category)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('This category is hidden.')));
      return;
    }
    if (locks.isLocked(category)) {
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => LockPasswordDialog(locks: locks),
      );
      if (!mounted || pin == null || !locks.unlock(category, pin)) return;
    }
    if (mounted) {
      await push(RecordingsLibraryScreen(provider: provider, type: type));
    }
  }

  Future<void> guide() =>
      push(LiveTvLaunchScreen(provider: provider, openGuide: true));
  void search() => push(
    DefaultTabController(
      length: provider.supportedTypes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Search'),
          bottom: TabBar(
            tabs: [
              for (final type in provider.supportedTypes) Tab(text: type.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final type in provider.supportedTypes)
              CatalogSearchScreen(
                provider: provider,
                type: type,
                onOpen: openItem,
              ),
          ],
        ),
      ),
    ),
  );
  Widget nav(
    String title,
    IconData icon,
    VoidCallback action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) => navigationKey(title, event),
      child: Tooltip(
        message: title,
        child: TextButton(
          focusNode: navNode(title),
          autofocus: title == 'Home',
          onFocusChange: (focused) {
            if (focused) {
              lastNav = title;
              final target = navNode(title).context;
              if (target != null) Scrollable.ensureVisible(target);
            }
          },
          onPressed: action,
          style:
              TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                foregroundColor: Colors.white70,
                backgroundColor: selected
                    ? Colors.white.withValues(alpha: .06)
                    : Colors.transparent,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ).copyWith(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? Colors.black
                      : Colors.white70,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? _accent
                      : selected
                      ? ((seriesActive || moviesActive)
                            ? _accent.withValues(alpha: .2)
                            : Colors.white.withValues(alpha: .06))
                      : Colors.transparent,
                ),
              ),
          child: Row(
            children: [
              Icon(icon, size: 18),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  Widget rail() => Focus(
    focusNode: railFocus,
    canRequestFocus: false,
    child: AnimatedContainer(
      key: const ValueKey('dashboard-sidebar'),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      width: collapsed
          ? 76
          : (MediaQuery.sizeOf(context).width / 1920 * 240).clamp(172.0, 250.0),
      color: const Color(0xff0b0d11),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              collapsed ? 'S' : 'Streamora',
              style: const TextStyle(
                color: _accent,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                nav(
                  'Home',
                  Icons.home_outlined,
                  openHome,
                  selected: !seriesActive && !moviesActive,
                ),
                if (provider.supportedTypes.contains(ContentType.live)) ...[
                  nav(
                    'Live TV',
                    Icons.tv_outlined,
                    () => browse(ContentType.live),
                  ),
                ],
                if (provider.supportedTypes.contains(ContentType.movies))
                  nav(
                    'Movies',
                    Icons.movie_outlined,
                    openMovies,
                    selected: moviesActive,
                  ),
                if (provider.supportedTypes.contains(ContentType.series))
                  nav(
                    'Series',
                    Icons.video_library_outlined,
                    openSeries,
                    selected: seriesActive,
                  ),
                if (provider.supportedTypes.contains(ContentType.live))
                  nav('TV Guide', Icons.view_list_outlined, guide),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  EpgProgramme? get current =>
      programmes.where((p) => p.isCurrent(DateTime.now())).firstOrNull;
  double get livePanelHeight =>
      (MediaQuery.sizeOf(context).height - 310).clamp(230.0, 260.0);

  Widget livePanel() => LayoutBuilder(
    builder: (context, size) {
      final now = Container(
        key: const ValueKey('dashboard-on-now'),
        height: livePanelHeight,
        decoration: BoxDecoration(
          color: const Color(0xff171f2b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              liveFocus.requestFocus();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              searchFocus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: OnNowPanel(
            entryFocusNode: onNowFocus,
            embedded: true,
            provider: provider,
            onOpen: selectFeature,
          ),
        ),
      );
      final highlightedNow = ListenableBuilder(
        listenable: onNowFocus,
        child: now,
        builder: (context, child) => DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: onNowFocus.hasFocus ? _accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: child,
        ),
      );
      if (size.maxWidth < 580) {
        return Column(
          children: [feature(), const SizedBox(height: 18), highlightedNow],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: feature()),
          const SizedBox(width: 18),
          Expanded(flex: 2, child: highlightedNow),
        ],
      );
    },
  );

  Widget feature() => ListenableBuilder(
    listenable: liveFocus,
    child: featureContent(),
    builder: (context, child) => AnimatedContainer(
      key: const ValueKey('dashboard-live-focus-border'),
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: liveFocus.hasFocus ? _accent : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    ),
  );

  Widget featureContent() {
    final item = featured;
    final programme = current;
    final seconds = programme?.end.difference(programme.start).inSeconds ?? 0;
    final fraction = programme == null || seconds <= 0
        ? null
        : (DateTime.now().difference(programme.start).inSeconds / seconds)
              .clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('dashboard-live-feature'),
      height: livePanelHeight,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff1c334f), Color(0xff132135)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: Colors.redAccent),
                    SizedBox(width: 7),
                    Text(
                      'LIVE TV',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  item?.name ?? 'Live TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  programme?.title ??
                      (loadingGuide
                          ? 'Loading programme guide...'
                          : 'Discover your live channels'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (fraction != null)
                  LinearProgressIndicator(
                    value: fraction,
                    minHeight: 3,
                    color: _accent,
                    backgroundColor: Colors.white12,
                  ),
                const SizedBox(height: 12),
                Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      onNowFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      returnToNavigation();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      searchFocus.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: FilledButton.icon(
                    focusNode: liveFocus,
                    onPressed: item == null
                        ? () => browse(ContentType.live)
                        : () => openItem(item),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: const Text('Watch Live', maxLines: 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 128,
                    maxHeight: 128,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      key: const ValueKey('dashboard-channel-artwork'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: item?.artwork == null
                          ? const Icon(
                              Icons.live_tv_rounded,
                              size: 48,
                              color: Colors.white54,
                            )
                          : CachedNetworkImage(
                              imageUrl: item!.artwork.toString(),
                              fit: BoxFit.contain,
                              memCacheWidth: 320,
                              maxWidthDiskCache: 320,
                              errorWidget: (_, _, _) => const Icon(
                                Icons.live_tv_rounded,
                                size: 48,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget continueWatching() => FutureBuilder<List<WatchEntry>>(
    future: watching,
    builder: (context, snapshot) {
      final entries = snapshot.data ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Continue watching',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Your unfinished movies and episodes will appear here.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: ListView.separated(
                key: const PageStorageKey('dashboard-history'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(5),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  final remaining =
                      ((entry.duration - entry.position).inSeconds / 60)
                          .ceil()
                          .clamp(0, 99999);
                  return Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        if (provider.supportedTypes.contains(
                          ContentType.live,
                        )) {
                          liveFocus.requestFocus();
                        } else {
                          searchFocus.requestFocus();
                        }
                        if (contentScroll.hasClients) contentScroll.jumpTo(0);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                          index == 0) {
                        returnToNavigation();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: _DashboardTitleCard(
                      key: ValueKey('${entry.item.type}:${entry.item.id}'),
                      item: entry.item,
                      onTap: () => openItem(entry.item),
                      metadata:
                          '${entry.episode == null ? '' : 'S${entry.episode!.season} E${entry.episode!.number} \u00b7 '}$remaining min left',
                      progress: entry.duration.inSeconds <= 0
                          ? 0
                          : (entry.position.inSeconds /
                                    entry.duration.inSeconds)
                                .clamp(0.0, 1.0),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  Widget dashboardHeader() => LayoutBuilder(
    builder: (context, size) {
      final searchButton = Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (headerIndices.isNotEmpty) focusHeader(headerIndices.first);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            returnToNavigation();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            if (provider.supportedTypes.contains(ContentType.live)) {
              liveFocus.requestFocus();
            } else {
              returnToNavigation();
            }
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: OutlinedButton.icon(
          key: const ValueKey('dashboard-search'),
          focusNode: searchFocus,
          onPressed: search,
          style: ButtonStyle(
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const Color(0xff284f77)
                  : Colors.transparent,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? _accent
                    : Colors.white24,
              ),
            ),
          ),
          icon: const Icon(Icons.search, size: 18),
          label: const Text('Search', style: TextStyle(fontSize: 12)),
        ),
      );
      final weather = const SizedBox(
        width: 200,
        child: WeatherPanel(compact: true),
      );
      if (size.maxWidth >= 650) {
        return Row(
          children: [
            searchButton,
            const Spacer(),
            weather,
            for (var i = 0; i < widget.headerActions.length; i++)
              headerAction(i),
          ],
        );
      }
      return Column(
        children: [
          Row(
            children: [
              searchButton,
              const Spacer(),
              Flexible(child: weather),
            ],
          ),
          if (widget.headerActions.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                children: [
                  for (var i = 0; i < widget.headerActions.length; i++)
                    headerAction(i),
                ],
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !seriesActive && !moviesActive) {
        final now = DateTime.now();
        if (exitPressed != null &&
            now.difference(exitPressed!) < const Duration(seconds: 2)) {
          unawaited(SystemNavigator.pop());
        } else {
          exitPressed = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press Back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
      if (!didPop &&
          (seriesActive || moviesActive) &&
          activeCatalog?.handleBack() != true) {
        openHome();
      }
    },
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xff17273b), Color(0xff0f1520), Color(0xff090d14)],
        ),
      ),
      child: Row(
        children: [
          rail(),
          Expanded(
            child: Focus(
              focusNode: contentFocus,
              canRequestFocus: false,
              child: IndexedStack(
                index: moviesActive
                    ? 2
                    : seriesActive
                    ? 1
                    : 0,
                children: [
                  SingleChildScrollView(
                    controller: contentScroll,
                    key: const PageStorageKey('dashboard-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dashboardHeader(),
                        const SizedBox(height: 14),
                        if (provider.supportedTypes.contains(
                          ContentType.live,
                        )) ...[
                          livePanel(),
                          const SizedBox(height: 16),
                        ],
                        continueWatching(),
                      ],
                    ),
                  ),
                  if (seriesCreated)
                    TickerMode(
                      enabled: seriesActive,
                      child: FadeTransition(
                        opacity: seriesFade.drive(
                          CurveTween(curve: Curves.easeOut),
                        ),
                        child: SeriesCatalogScreen(
                          key: seriesCatalog,
                          provider: provider,
                          onNavigation: () => navNode('Series').requestFocus(),
                          onSettings: widget.onSettings,
                          headerActions: widget.headerActions,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  if (moviesCreated)
                    TickerMode(
                      enabled: moviesActive,
                      child: FadeTransition(
                        opacity: seriesFade.drive(
                          CurveTween(curve: Curves.easeOut),
                        ),
                        child: SeriesCatalogScreen(
                          key: movieCatalog,
                          type: ContentType.movies,
                          provider: provider,
                          onNavigation: () => navNode('Movies').requestFocus(),
                          onSettings: widget.onSettings,
                          headerActions: widget.headerActions,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Focus effects are local: dashboard, EPG requests and artwork stay stable.
class _DashboardTitleCard extends StatefulWidget {
  final ContentItem item;
  final String metadata;
  final double? progress;
  final VoidCallback onTap;
  const _DashboardTitleCard({
    super.key,
    required this.item,
    required this.metadata,
    this.progress,
    required this.onTap,
  });
  @override
  State<_DashboardTitleCard> createState() => _DashboardTitleCardState();
}

class _DashboardTitleCardState extends State<_DashboardTitleCard> {
  bool focused = false;
  String? prefetched;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = widget.item.artwork?.toString();
    if (uri == null || uri == prefetched) return;
    prefetched = uri;
    // Only lazily constructed, visible/adjacent cards warm the image cache.
    unawaited(
      precacheImage(
        ResizeImage(CachedNetworkImageProvider(uri, maxWidth: 480), width: 480),
        context,
        onError: (_, _) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: AnimatedScale(
      scale: focused && !MediaQuery.disableAnimationsOf(context) ? 1.04 : 1,
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: focused ? const Color(0xff293d54) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: focused ? _accent : Colors.transparent),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: widget.onTap,
            onFocusChange: (value) {
              setState(() => focused = value);
              if (value) {
                final scrollable = Scrollable.maybeOf(
                  context,
                  axis: Axis.horizontal,
                );
                final renderObject = context.findRenderObject();
                if (scrollable != null && renderObject != null) {
                  scrollable.position.ensureVisible(
                    renderObject,
                    alignment: .35,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOut,
                  );
                }
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 212,
                    height: 86,
                    child: ContinueWatchingArtwork(item: widget.item),
                  ),
                ),
                if (widget.progress != null) ...[
                  const SizedBox(height: 5),
                  LinearProgressIndicator(
                    value: widget.progress,
                    minHeight: 3,
                    color: _accent,
                    backgroundColor: Colors.white12,
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  widget.item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
