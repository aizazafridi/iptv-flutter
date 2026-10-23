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
import 'tv_guide_screen.dart';
import 'smooth_page_route.dart';
import 'my_list_button.dart';

const _accent = Color(0xff64b5f6);
const _panel = Color(0xff191d24);

class StreamoraDashboard extends StatefulWidget {
  final Session session;
  final AppAppearance appearance;
  final VoidCallback onSettings;
  const StreamoraDashboard({
    super.key,
    required this.session,
    required this.appearance,
    required this.onSettings,
  });
  @override
  State<StreamoraDashboard> createState() => _StreamoraDashboardState();
}

class _StreamoraDashboardState extends State<StreamoraDashboard> {
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
  @override
  void initState() {
    super.initState();
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
    refresh?.cancel();
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
    final entries = await history.entries();
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
    return entries
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
    BrowseScreen(provider: provider, type: type, appearance: widget.appearance),
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

  Future<void> favourites() async {
    final type = await chooseType('My list');
    if (type == null || !mounted) return;
    final rows = await visible(await MyList.forProvider(provider).items(type));
    if (!mounted) return;
    final selected = await showDialog<ContentItem>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('My list - ${type.label}'),
        children: rows.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Your list is empty'),
                ),
              ]
            : rows
                  .map(
                    (item) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, item),
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
      ),
    );
    if (selected != null && mounted) await openItem(selected);
  }

  Future<void> guide() => push(TvGuideScreen(provider: provider));
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    child: TextButton.icon(
      onPressed: action,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: selected ? Colors.black : Colors.white70,
        backgroundColor: selected ? _accent : Colors.transparent,
        minimumSize: const Size(double.infinity, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13),
      ),
      icon: Icon(icon, size: 17),
      label: Text(title),
    ),
  );
  Widget rail() => Container(
    width: 172,
    color: const Color(0xff0b0d11),
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Text(
            'Streamora',
            style: TextStyle(
              color: _accent,
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              nav('Home', Icons.home_outlined, () {}, selected: true),
              if (provider.supportedTypes.contains(ContentType.live)) ...[
                nav(
                  'Live TV',
                  Icons.tv_outlined,
                  () => browse(ContentType.live),
                ),
                nav('TV Guide', Icons.view_list_outlined, guide),
              ],
              if (provider.supportedTypes.contains(ContentType.movies))
                nav(
                  'Movies',
                  Icons.movie_outlined,
                  () => browse(ContentType.movies),
                ),
              if (provider.supportedTypes.contains(ContentType.series))
                nav(
                  'Series',
                  Icons.video_library_outlined,
                  () => browse(ContentType.series),
                ),
              nav('My list', Icons.check_circle_outline, favourites),
              nav('Recordings', Icons.fiber_manual_record_outlined, recordings),
            ],
          ),
        ),
        nav('Settings', Icons.settings_outlined, widget.onSettings),
        const SizedBox(height: 12),
      ],
    ),
  );
  EpgProgramme? get current =>
      programmes.where((p) => p.isCurrent(DateTime.now())).firstOrNull;
  Widget livePanel() => Container(
    decoration: BoxDecoration(
      color: const Color(0xff202c3e),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, size) {
        final now = SizedBox(
          height: 230,
          child: OnNowPanel(
            embedded: true,
            provider: provider,
            onOpen: selectFeature,
          ),
        );
        if (size.maxWidth < 480) return Column(children: [feature(), now]);
        return Row(
          children: [
            Expanded(flex: 2, child: feature()),
            const SizedBox(
              height: 190,
              child: VerticalDivider(width: 1, color: Colors.white12),
            ),
            Expanded(child: now),
          ],
        );
      },
    ),
  );

  Widget feature() {
    final item = featured;
    final programme = current;
    final fraction = programme == null
        ? null
        : (DateTime.now().difference(programme.start).inSeconds /
                  programme.end.difference(programme.start).inSeconds)
              .clamp(0.0, 1.0);
    return Container(
      height: 230,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.circle, size: 7, color: Colors.redAccent),
              SizedBox(width: 6),
              Text(
                'LIVE TV',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
          const SizedBox(height: 6),
          Text(
            programme?.title ??
                (loadingGuide
                    ? 'Loading programme guide...'
                    : 'Discover your live channels'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (fraction != null)
            LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: _accent,
              backgroundColor: Colors.white12,
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: item == null
                    ? () => browse(ContentType.live)
                    : () => openItem(item),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Watch now'),
              ),
              if (item != null) ...[
                const SizedBox(width: 12),
                MyListButton(provider: provider, item: item, compact: true),
              ],
            ],
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Your unfinished movies and episodes will appear here.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            SizedBox(
              height: 155,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, index) {
                  final entry = entries[index];
                  return SizedBox(
                    width: 200,
                    child: InkWell(
                      onTap: () => openItem(entry.item),
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 100,
                              width: 200,
                              child: entry.item.artwork == null
                                  ? const ColoredBox(
                                      color: _panel,
                                      child: Icon(Icons.movie_outlined),
                                    )
                                  : Image.network(
                                      entry.item.artwork.toString(),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const ColoredBox(
                                            color: _panel,
                                            child: Icon(Icons.movie_outlined),
                                          ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            minHeight: 3,
                            color: _accent,
                            backgroundColor: Colors.white12,
                            value: entry.duration.inSeconds > 0
                                ? (entry.position.inSeconds /
                                          entry.duration.inSeconds)
                                      .clamp(0.0, 1.0)
                                : 0,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            entry.item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (entry.episode != null)
                            Text(
                              'S${entry.episode!.season} E${entry.episode!.number}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xff101217),
    child: Row(
      children: [
        rail(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: search,
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: Colors.white54,
                        backgroundColor: _panel,
                        padding: const EdgeInsets.all(16),
                        shape: const StadiumBorder(),
                        side: const BorderSide(color: Colors.white12),
                      ),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text(
                        'Search channels, movies, series',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (constraints.maxWidth >= 650)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: livePanel()),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: constraints.maxWidth >= 1000 ? 260 : 220,
                          child: const WeatherPanel(),
                        ),
                      ],
                    )
                  else ...[
                    livePanel(),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(width: 300, child: WeatherPanel()),
                    ),
                  ],
                  const SizedBox(height: 22),
                  continueWatching(),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
