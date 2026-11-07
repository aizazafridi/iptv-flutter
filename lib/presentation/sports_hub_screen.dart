import 'sports_event_details_layout.dart';
import 'sports_match_graphics.dart';
import 'package:flutter/services.dart';
import '../application/live_score_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../application/browsing_mode.dart';
import '../application/category_locks.dart';
import '../application/live_favourite_groups.dart';
import '../application/my_list.dart';
import '../application/sports_channel_matcher.dart';
import '../application/sports_favorites.dart';
import '../application/sports_repository.dart';
import '../application/watch_history.dart';
import '../data/the_sports_db_provider.dart';
import '../data/artwork_repository.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../domain/sports.dart';
import 'activation_text_field.dart';
import 'shared_artwork_image.dart';
import 'smooth_page_route.dart';

const _blue = Color(0xff64b5f6);
String sportsStatus(SportsEvent event, {bool liveFeed = false}) =>
    event.scoreUpdate != null
    ? (event.scoreUpdate!.fresh
          ? event.scoreUpdate!.status.name
          : 'Score stale')
    : event.status == SportsEventStatus.live && !liveFeed
    ? 'Live status unconfirmed'
    : event.status.name;
String sportsCardTime(DateTime? time) {
  if (time == null) return 'Time unavailable';
  final local = time.toLocal();
  final now = DateTime.now();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final label = day == today
      ? 'Today'
      : day == tomorrow
      ? 'Tomorrow'
      : '${local.day}/${local.month}/${local.year}';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  return '$label \u00b7 $hour:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
}

String sportsTime(DateTime? time) {
  if (time == null) return 'Time unavailable';
  final d = time.toLocal();
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class SportsHubScreen extends StatefulWidget {
  final IptvProvider provider;
  final Future<void> Function(ContentItem) onWatch;
  final SportsDataProvider? sportsProvider;
  final LiveScoreService? liveScores;
  const SportsHubScreen({
    super.key,
    required this.provider,
    required this.onWatch,
    this.sportsProvider,
    this.liveScores,
  });
  @override
  State<SportsHubScreen> createState() => _SportsHubScreenState();
}

class _SportsHubScreenState extends State<SportsHubScreen> {
  late final api = widget.sportsProvider ?? TheSportsDbProvider();
  late final repository = SportsRepository(api);
  late final scoreService = widget.liveScores ?? LiveScoreService(api);
  late final favorites = SportsFavorites(
    WatchHistory.forProvider(widget.provider).scope,
  );
  List<Sport> sports = [];
  // Cricket is a supported schedule filter even when the limited free sports
  // catalogue omits it. This does not imply complete fixture coverage.
  List<String> get sportFilters =>
      {'Cricket', ...sports.map((s) => s.name), 'Motorsport'}.toList();
  List<SportsLeague> leagues = [];
  List<SportsEvent> events = [];
  List<ContentItem> channels = [];
  String? sport, league, error, channelsError;
  String section = 'Today';
  bool loading = true;
  int generation = 0;
  String? selectionKey;
  final eventFocus = <String, FocusNode>{};
  final scroll = ScrollController();
  DateTime? updated;
  Timer? midnight, liveRefresh;
  @override
  void initState() {
    super.initState();
    favorites.addListener(favoritesChanged);
    BrowsingModeSettings.instance.addListener(modeChanged);
    if (api is TheSportsDbProvider) {
      (api as TheSportsDbProvider).cache.addListener(cacheChanged);
    }
    unawaited(start());
    unawaited(loadChannels());
    if (scoreService.available) {
      liveRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
        if (['Live', 'Today', 'Results'].contains(section) &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed &&
            ModalRoute.of(context)?.isCurrent == true) {
          unawaited(load());
        }
      });
    }
    final now = DateTime.now();
    midnight = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () => load(),
    );
  }

  void modeChanged() {
    if (mounted) setState(() {});
  }

  void favoritesChanged() {
    if (mounted) {
      setState(() {});
      unawaited(load());
    }
  }

  void cacheChanged() {
    if (!mounted) return;
    final cache = (api as TheSportsDbProvider).cache;
    if (cache.error != null) {
      setState(() => error = cache.error);
      return;
    }
    if (cache.updatedIdentity?.contains('all_sports.php') == true) {
      unawaited(
        api.getSports().then((rows) {
          if (mounted) setState(() => sports = rows);
        }, onError: (Object _, StackTrace _) {}),
      );
      return;
    }
    if (cache.updatedIdentity?.contains('all_leagues.php') == true) {
      unawaited(
        api.getLeagues().then((rows) {
          if (mounted) setState(() => leagues = rows);
        }, onError: (Object _, StackTrace _) {}),
      );
      return;
    }
    // A successful background refresh is visible without leaving this screen.
    if (!loading) unawaited(load());
  }

  Future<void> start() async {
    try {
      await favorites.load();
    } catch (_) {
      error = 'Could not read followed teams. Please retry.';
    }
    // Fixtures and IPTV channels remain independent of sport/league catalogues.
    unawaited(
      api.getSports().then((rows) {
        if (mounted) setState(() => sports = rows);
      }, onError: (Object _, StackTrace _) {}),
    );
    unawaited(
      api.getLeagues().then((rows) {
        if (mounted) setState(() => leagues = rows);
      }, onError: (Object _, StackTrace _) {}),
    );
    await load();
  }

  Future<void> loadChannels() async {
    try {
      final all = await widget.provider.getAllItems(ContentType.live);
      final visible = await CategoryLocks.forProvider(
        widget.provider,
      ).visibleItems(all, excludeConfiguredLocks: true);
      final saved = await MyList.forProvider(
        widget.provider,
      ).items(ContentType.live);
      final groups = LiveFavouriteGroups.forProvider(widget.provider);
      await groups.load();
      final grouped = {
        for (final g in groups.groups)
          if (SportsChannelMatcher.sportsChannel(g.name)) ...g.channels,
      };
      final savedIds = saved.map((x) => x.id).toSet();
      final rows = visible
          .where(
            (x) =>
                grouped.contains(x.id) ||
                SportsChannelMatcher.sportsChannel(x.name),
          )
          .toList();
      int priority(ContentItem x) => grouped.contains(x.id)
          ? 0
          : savedIds.contains(x.id)
          ? 1
          : 2;
      rows.sort((a, b) => priority(a).compareTo(priority(b)));
      if (mounted) {
        setState(() {
          channels = rows;
          channelsError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => channelsError = 'Unable to load sports channels.');
      }
    }
  }

  Future<void> load() async {
    final key =
        '$section|$sport|$league|${favorites.teams.keys.join(',')}|${favorites.leagues.keys.join(',')}';
    if (key != selectionKey && api is TheSportsDbProvider) {
      (api as TheSportsDbProvider).cancelQueuedSchedules();
    }
    selectionKey = key;
    final version = ++generation;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      List<SportsEvent> rows;
      if (section == 'Live') {
        var fixtures = <SportsEvent>[];
        try {
          fixtures = await repository.today(DateTime.now(), sport: sport);
        } catch (_) {}
        rows = await scoreService.live(fixtures);
      } else if (section == 'Today') {
        rows = await repository.today(DateTime.now(), sport: sport);
      } else if (section == 'My Teams') {
        rows = await repository.followed(favorites.teams.keys, []);
      } else if (section == 'Upcoming' && sport == 'Motorsport') {
        rows = await repository.upcomingMotorsport(
          DateTime.now(),
          leagues,
          leagueId: league,
        );
      } else if (league != null) {
        rows = section == 'Results'
            ? await api.getRecentResults(leagueId: league)
            : await api.getUpcomingEvents(leagueId: league);
      } else if (favorites.teams.isNotEmpty || favorites.leagues.isNotEmpty) {
        rows = await repository.followed(
          favorites.teams.keys,
          favorites.leagues.keys,
          results: section == 'Results',
        );
      } else if (section == 'Results') {
        rows = (await repository.today(
          DateTime.now().subtract(const Duration(days: 1)),
          sport: sport,
        )).where((e) => e.status == SportsEventStatus.finished).toList();
      } else {
        rows = await repository.today(
          DateTime.now().add(const Duration(days: 1)),
          sport: sport,
        );
      }
      if (section == 'Today' || section == 'Results') {
        rows = await scoreService.enrich(rows);
      }
      if (section == 'Upcoming' || section == 'My Teams') {
        rows = rows
            .where(
              (e) =>
                  e.startTimeUtc != null &&
                  e.startTimeUtc!.isAfter(DateTime.now().toUtc()) &&
                  e.status != SportsEventStatus.cancelled &&
                  e.status != SportsEventStatus.finished,
            )
            .toList();
      }
      if (section == 'Live') {
        rows = rows
            .where(
              (e) =>
                  e.scoreUpdate?.status == SportsEventStatus.live ||
                  (e.scoreUpdate == null &&
                      api.supportsLive &&
                      e.status == SportsEventStatus.live),
            )
            .toList();
      }
      rows = repository.unique(
        rows.where((e) => sport == null || e.sportId == sport),
      );
      // Stable ordering within followed/non-followed groups preserves time order.
      bool followed(SportsEvent e) =>
          favorites.teams.containsKey(e.homeTeamId) ||
          favorites.teams.containsKey(e.awayTeamId);
      rows = [...rows.where(followed), ...rows.where((e) => !followed(e))];
      if (mounted && version == generation) {
        setState(() {
          events = rows;
          scoreService.diagnostics();
          updated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && version == generation) {
        setState(
          () => error = e is SportsDataException
              ? e.message
              : 'Unable to update sports information.',
        );
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  Future<void> follow(String id, String name, {bool league = false}) async {
    try {
      await favorites.toggle(id, name, league: league);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save favorites. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> watch(ContentItem selected) async {
    // Resolve the original ID from this provider's current visible playlist.
    try {
      final all = await widget.provider.getAllItems(ContentType.live);
      final visible = await CategoryLocks.forProvider(
        widget.provider,
      ).visibleItems(all, excludeConfiguredLocks: true);
      final current = visible.where((x) => x.id == selected.id).firstOrNull;
      if (current == null) {
        throw const SportsDataException('This channel is no longer available.');
      }
      await widget.onWatch(current);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This channel is unavailable. Please refresh the playlist.',
            ),
          ),
        );
      }
    }
  }

  final verifiedChannels = <String, ContentItem>{};
  Future<void> followEvent(SportsEvent event) async {
    final teams = <String, String>{
      if (event.homeTeamId != null && event.homeTeamName != null)
        event.homeTeamId!: event.homeTeamName!,
      if (event.awayTeamId != null && event.awayTeamName != null)
        event.awayTeamId!: event.awayTeamName!,
    };
    if (teams.isEmpty) {
      await findTeams();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: favorites,
        builder: (_, _) => SimpleDialog(
          title: const Text('Follow Teams'),
          children: [
            for (final team in teams.entries)
              SimpleDialogOption(
                onPressed: () => follow(team.key, team.value),
                child: Text(
                  '${favorites.teams.containsKey(team.key) ? 'Unfollow' : 'Follow'} ${team.value}',
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> details(SportsEvent event) async {
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => SportsEventDetailsScreen(
          event: event,
          api: api,
          favorites: favorites,
          channels: channels,
          provider: widget.provider,
          onFollow: follow,
          onChannelMatches: (matches) {
            final verified = matches
                .where((m) => m.confidence == SportsChannelConfidence.verified)
                .firstOrNull;
            if (mounted) {
              setState(() {
                if (verified != null) {
                  verifiedChannels[event.id] = verified.channel;
                } else {
                  verifiedChannels.remove(event.id);
                }
              });
            }
          },
          scoreService: scoreService,
          onWatch: watch,
        ),
      ),
    );
    if (mounted) eventFocus[event.id]?.requestFocus();
  }

  Future<void> findTeams() async {
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => SportsTeamSearchScreen(
          api: api,
          favorites: favorites,
          onFollow: follow,
        ),
      ),
    );
  }

  Future<void> chooseLeague() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Leagues'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(dialog);
              setState(() => league = null);
              unawaited(load());
            },
            child: const Text('All available leagues'),
          ),
          for (final l in leagues.where(
            (l) => sport == null || l.sportId == sport,
          ))
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialog);
                setState(() => league = l.id);
                unawaited(load());
              },
              child: Text(l.name),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    midnight?.cancel();
    liveRefresh?.cancel();
    scroll.dispose();
    for (final n in eventFocus.values) {
      n.dispose();
    }
    favorites.removeListener(favoritesChanged);
    favorites.dispose();
    BrowsingModeSettings.instance.removeListener(modeChanged);
    if (api is TheSportsDbProvider) {
      (api as TheSportsDbProvider).cache.removeListener(cacheChanged);
    }
    if (widget.liveScores == null) scoreService.dispose();
    if (widget.sportsProvider == null) api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lite = BrowsingModeSettings.instance.lite;
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xff061321))),
        if (!lite)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 230,
            child: Image.asset(
              'assets/sports/stadium_header.jpg',
              fit: BoxFit.cover,
              cacheWidth: 960,
              cacheHeight: 320,
              excludeFromSemantics: true,
            ),
          ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x48061321), Color(0xff061321)],
                  stops: [0, .42],
                ),
              ),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 44,
            title: const Text(
              'Sports Hub',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            iconTheme: const IconThemeData(size: 19),
            actionsIconTheme: const IconThemeData(
              size: 19,
              color: Color(0xffbdcce0),
            ),
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Find Teams',
                onPressed: findTeams,
                icon: const Icon(Icons.search_outlined),
              ),
              IconButton(
                tooltip: 'Following',
                onPressed: showFollowed,
                icon: const Icon(Icons.star_border_rounded, color: _blue),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  unawaited(load());
                  unawaited(loadChannels());
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: FocusTraversalGroup(
            child: CustomScrollView(
              controller: scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverList.list(
                    children: [
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            sportsChip('All', sport == null, () {
                              setState(() {
                                sport = null;
                                league = null;
                              });
                              unawaited(load());
                            }),
                            for (final name in sportFilters)
                              sportsChip(
                                name == 'Soccer' ? 'Football' : name,
                                sport == name,
                                () {
                                  setState(() {
                                    sport = name;
                                    league = null;
                                  });
                                  unawaited(load());
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tab in [
                            'Live',
                            'Today',
                            'Upcoming',
                            'Results',
                            'My Teams',
                          ])
                            sportsChip(tab, section == tab, () {
                              setState(() => section = tab);
                              unawaited(load());
                            }, pill: false),
                          sportsChip(
                            leagues
                                    .where((l) => l.id == league)
                                    .firstOrNull
                                    ?.name ??
                                'Leagues',
                            league != null,
                            chooseLeague,
                            pill: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (api.limitedCoverage)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (dialog) => AlertDialog(
                                title: const Text('Sports Data Coverage'),
                                content: const Text(
                                  'Showing available matches. Full schedule coverage requires an upgraded sports data plan. Live-score coverage and refresh frequency depend on each provider.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialog),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                            icon: const Icon(Icons.info_outline, size: 14),
                            label: const Text(
                              'Coverage info',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ),
                      if (scoreService.providerNotice != null)
                        Text(
                          scoreService.providerNotice!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white60,
                          ),
                        ),
                      if (updated != null)
                        Text(
                          'Last checked ${sportsTime(updated)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                      if (loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      if (error != null)
                        Row(
                          children: [
                            Expanded(child: Text(error!)),
                            TextButton(
                              onPressed: load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      if (section == 'Live' && !scoreService.available)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(scoreService.unavailableMessage),
                        )
                      else if (section == 'My Teams' && favorites.teams.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Follow your favorite teams to see their matches here.',
                            ),
                            TextButton(
                              onPressed: findTeams,
                              child: const Text('Find Teams'),
                            ),
                          ],
                        )
                      else if (!loading && events.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matches available for this date.'),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent >= 640
                          ? 2
                          : 1;
                      return SliverGrid.builder(
                        itemCount: events.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisExtent: lite ? 232 : 266,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          return SportsEventCard(
                            key: ValueKey(event.id),
                            event: event,
                            lite: lite,
                            liveFeed: section == 'Live' && api.supportsLive,
                            followed:
                                favorites.teams.containsKey(event.homeTeamId) ||
                                favorites.teams.containsKey(event.awayTeamId),
                            focusNode: eventFocus.putIfAbsent(
                              event.id,
                              () => FocusNode(
                                debugLabel: 'sports event ${event.id}',
                              ),
                            ),
                            onOpen: () => details(event),
                            onFollow: () => followEvent(event),
                            onWatch:
                                (verifiedChannels[event.id] == null ||
                                    !(event.scoreIsLive ||
                                        (api.supportsLive &&
                                            event.status ==
                                                SportsEventStatus.live)))
                                ? null
                                : () => watch(verifiedChannels[event.id]!),
                            onMove: (delta) {
                              final next = index + delta;
                              if (next < 0 || next >= events.length) return;
                              final node = eventFocus.putIfAbsent(
                                events[next].id,
                                () => FocusNode(
                                  debugLabel: 'sports event ${events[next].id}',
                                ),
                              );
                              if (node.context != null) {
                                node.requestFocus();
                                return;
                              }
                              if (scroll.hasClients) {
                                scroll.jumpTo(
                                  (scroll.offset +
                                          (delta.isNegative ? -1 : 1) *
                                              (lite ? 242 : 276))
                                      .clamp(
                                        0,
                                        scroll.position.maxScrollExtent,
                                      ),
                                );
                              }
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) node.requestFocus();
                              });
                              WidgetsBinding.instance.ensureVisualUpdate();
                            },
                            columns: columns,
                          );
                        },
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: Color(0xff344154)),
                        const SizedBox(height: 12),
                        Text(
                          api.attribution,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> showFollowed() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: favorites,
        builder: (_, _) => SimpleDialog(
          title: const Text('Following'),
          children: [
            if (favorites.teams.isEmpty && favorites.leagues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No followed teams or leagues yet.'),
              ),
            for (final t in favorites.teams.entries)
              SimpleDialogOption(
                onPressed: () => follow(t.key, t.value),
                child: Text('Unfollow ${t.value}'),
              ),
            for (final l in favorites.leagues.entries)
              SimpleDialogOption(
                onPressed: () => follow(l.key, l.value, league: true),
                child: Text('Unfollow ${l.value}'),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle sportsFocusStyle(ButtonStyle style) => style.copyWith(
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: _blue, width: 2)
        : style.side?.resolve(states) ??
              const BorderSide(color: Colors.white24),
  ),
  overlayColor: WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.focused) ? const Color(0x303F83BD) : null,
  ),
);

Widget sportsChip(
  String title,
  bool selected,
  VoidCallback onPressed, {
  bool pill = true,
}) => Padding(
  padding: const EdgeInsets.only(right: 6),
  child: OutlinedButton(
    style: sportsFocusStyle(
      OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        backgroundColor: selected
            ? (pill ? const Color(0xff396397) : const Color(0xff314b6a))
            : const Color(0xff202c3e),
        side: const BorderSide(color: Colors.transparent),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(pill ? 24 : 8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    ),
    onPressed: onPressed,
    child: Text(title),
  ),
);

class SportsLogo extends StatelessWidget {
  final String? url;
  const SportsLogo(this.url, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: url == null || BrowsingModeSettings.instance.lite
        ? const Icon(Icons.sports, color: Colors.white38)
        : SharedArtworkImage(
            imageUrl:
                Uri.tryParse(url!)?.host.endsWith('thesportsdb.com') == true
                ? '${url!}/tiny'
                : url!,
            kind: ArtworkKind.logo,
            fit: BoxFit.contain,
            errorWidget: (_, _, _) =>
                const Icon(Icons.sports, color: Colors.white38),
          ),
  );
}

class SportsEventCard extends StatefulWidget {
  final SportsEvent event;
  final bool lite, followed, liveFeed;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final VoidCallback? onFollow, onWatch;
  final ValueChanged<int>? onMove;
  final int columns;
  const SportsEventCard({
    super.key,
    required this.event,
    required this.lite,
    required this.followed,
    required this.focusNode,
    required this.onOpen,
    this.liveFeed = false,
    this.onFollow,
    this.onWatch,
    this.onMove,
    this.columns = 2,
  });
  @override
  State<SportsEventCard> createState() => _SportsEventCardState();
}

class _SportsEventCardState extends State<SportsEventCard> {
  bool focused = false;
  final detailsFocus = FocusNode(),
      followFocus = FocusNode(),
      watchFocus = FocusNode();
  @override
  void dispose() {
    detailsFocus.dispose();
    followFocus.dispose();
    watchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final live =
        e.scoreIsLive ||
        (e.scoreUpdate == null &&
            widget.liveFeed &&
            e.status == SportsEventStatus.live);
    final motion = !widget.lite && !MediaQuery.disableAnimationsOf(context);
    Widget action(
      String label,
      IconData icon,
      FocusNode node,
      VoidCallback callback,
    ) => Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 5),
        child: OutlinedButton(
          focusNode: node,
          onPressed: callback,
          style: sportsFocusStyle(
            OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xff203d5b),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: Colors.transparent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) {
        setState(() => focused = value);
        if (value) {
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            duration: Duration(milliseconds: motion ? 160 : 0),
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (node.hasPrimaryFocus) {
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select) {
            widget.onOpen();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            detailsFocus.requestFocus();
            return KeyEventResult.handled;
          }
          if (widget.onMove != null &&
              [
                LogicalKeyboardKey.arrowLeft,
                LogicalKeyboardKey.arrowRight,
              ].contains(key)) {
            widget.onMove!(key == LogicalKeyboardKey.arrowLeft ? -1 : 1);
            return KeyEventResult.handled;
          }
        } else {
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight) {
            final actions = [
              if (widget.onWatch != null) watchFocus,
              detailsFocus,
              if (widget.onFollow != null) followFocus,
            ];
            final current = actions.indexWhere((n) => n.hasFocus);
            if (current >= 0) {
              actions[(current + (key == LogicalKeyboardKey.arrowLeft ? -1 : 1))
                      .clamp(0, actions.length - 1)]
                  .requestFocus();
            }
            return KeyEventResult.handled;
          }

          if (key == LogicalKeyboardKey.arrowUp) {
            node.requestFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown && widget.onMove != null) {
            widget.onMove!(widget.columns);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: focused && motion ? 1.015 : 1,
        duration: Duration(milliseconds: motion ? 170 : 0),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: Duration(milliseconds: motion ? 170 : 0),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.lite
                  ? const [Color(0xff142338), Color(0xff142338)]
                  : e.status == SportsEventStatus.finished
                  ? const [Color(0xff122d37), Color(0xff142738)]
                  : live
                  ? const [Color(0xff073458), Color(0xff172443)]
                  : const [Color(0xff132e49), Color(0xff172438)],
            ),
            border: Border.all(
              color: focused ? _blue : const Color(0xff344860),
              width: focused ? 2 : 1,
            ),
            boxShadow: focused && !widget.lite
                ? [
                    BoxShadow(
                      color: _blue.withValues(alpha: .35),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sportsIcon(e.sportId), color: _blue, size: 15),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      (e.sportId == 'Soccer'
                              ? 'Football'
                              : e.sportId ?? 'Sport')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xffb9d9fa),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: live
                          ? const Color(0xffd92538)
                          : const Color(0xff25394d),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      live ? 'LIVE' : sportsStatus(e).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Expanded(
                child: InkWell(
                  canRequestFocus: false,
                  onTap: widget.onOpen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      if (e.homeTeamName != null && e.awayTeamName != null)
                        SportsScoreboard(event: e, lite: widget.lite)
                      else
                        Text(
                          e.displayScore ?? sportsCardTime(e.startTimeUtc),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.1,
                          ),
                        ),
                      if (e.displayScore == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            sportsCardTime(e.startTimeUtc),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (e.scoreUpdate != null)
                Text(
                  e.scoreUpdate!.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8, color: Colors.white60),
                ),
              if (e.scoreUpdate?.updatedAt != null)
                Text(
                  'Provider updated: ${sportsTime(e.scoreUpdate!.updatedAt)}',
                  style: const TextStyle(fontSize: 8, color: Colors.white54),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (widget.onWatch != null)
                    action(
                      'Watch Live',
                      Icons.play_arrow,
                      watchFocus,
                      widget.onWatch!,
                    ),
                  action(
                    'Match Details',
                    Icons.info_outline,
                    detailsFocus,
                    widget.onOpen,
                  ),
                  if (widget.onFollow != null)
                    action(
                      e.homeTeamId != null || e.awayTeamId != null
                          ? (widget.followed ? 'Following' : 'Follow')
                          : 'Find Teams',
                      widget.followed ? Icons.star : Icons.star_border,
                      followFocus,
                      widget.onFollow!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SportsChannelTile extends StatelessWidget {
  final ContentItem channel;
  final String label;
  final VoidCallback onWatch;
  const SportsChannelTile({
    super.key,
    required this.channel,
    required this.label,
    required this.onWatch,
  });
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onWatch,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.all(14),
      foregroundColor: Colors.white,
      alignment: Alignment.centerLeft,
    ),
    child: Row(
      children: [
        if (!BrowsingModeSettings.instance.lite) ...[
          SizedBox(
            width: 38,
            height: 30,
            child: channel.artwork == null
                ? const Icon(Icons.tv)
                : SharedArtworkImage(
                    imageUrl: channel.artwork.toString(),
                    kind: ArtworkKind.logo,
                    fit: BoxFit.contain,
                  ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(child: Text(channel.name)),
        Text(label, style: const TextStyle(color: _blue, fontSize: 12)),
      ],
    ),
  );
}

typedef SportsFollow =
    Future<void> Function(String id, String name, {bool league});

class SportsEventDetailsScreen extends StatefulWidget {
  final SportsEvent event;
  final SportsDataProvider api;
  final SportsFavorites favorites;
  final List<ContentItem> channels;
  final IptvProvider provider;
  final SportsFollow onFollow;
  final ValueChanged<List<SportsChannelMatch>>? onChannelMatches;
  final LiveScoreService? scoreService;
  final Future<void> Function(ContentItem) onWatch;
  const SportsEventDetailsScreen({
    super.key,
    required this.event,
    this.scoreService,
    this.onChannelMatches,
    required this.api,
    required this.favorites,
    required this.channels,
    required this.provider,
    required this.onFollow,
    required this.onWatch,
  });
  @override
  State<SportsEventDetailsScreen> createState() =>
      _SportsEventDetailsScreenState();
}

class _SportsEventDetailsScreenState extends State<SportsEventDetailsScreen> {
  Timer? scoreTimer;
  late SportsEvent event = widget.event;
  List<SportsChannelMatch>? matches;
  bool matching = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(enrich());
    if (widget.scoreService?.available == true) {
      scoreTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
        if (!mounted ||
            ModalRoute.of(context)?.isCurrent != true ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        await widget.scoreService!.refresh();
        if (mounted) setState(() => event = widget.scoreService!.latest(event));
      });
    }
  }

  @override
  void dispose() {
    scoreTimer?.cancel();
    super.dispose();
  }

  Future<void> enrich() async {
    if (event.supplemental) return;
    try {
      var detail = await widget.api.getEventDetails(event.id);
      if (detail != null && widget.scoreService != null) {
        detail = (await widget.scoreService!.enrich([detail])).single;
      }
      final ready = detail;
      if (mounted && ready != null) setState(() => event = ready);
    } catch (_) {}
  }

  Future<void> findChannels() async {
    if (matching) return;
    setState(() {
      matching = true;
      error = null;
    });
    try {
      final all = await widget.provider.getAllItems(ContentType.live);
      final rows = await CategoryLocks.forProvider(
        widget.provider,
      ).visibleItems(all, excludeConfiguredLocks: true);
      final epg = <String, List<EpgProgramme>>{};
      final p = widget.provider;
      if (p is EpgProvider) {
        // Query only on explicit discovery, two lanes, bounded candidates.
        final candidates = rows
            .where(
              (c) =>
                  SportsChannelMatcher.sportsChannel(c.name) ||
                  widget.channels.any((s) => s.id == c.id),
            )
            .take(24)
            .toList();
        var index = 0;
        Future<void> lane() async {
          while (mounted &&
              ModalRoute.of(context)?.isCurrent == true &&
              index < candidates.length) {
            final c = candidates[index++];
            try {
              epg[c.id] = await (p as EpgProvider).getEpg(c);
              if (mounted) {
                setState(
                  () =>
                      matches = SportsChannelMatcher().match(event, rows, epg),
                );
              }
            } catch (_) {}
          }
        }

        await Future.wait([lane(), lane()]);
      }
      final found = SportsChannelMatcher().match(event, rows, epg);
      if (mounted) {
        setState(() => matches = found);
        widget.onChannelMatches?.call(found);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to find channels. Please retry.');
      }
    } finally {
      if (mounted) setState(() => matching = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff0a111d),
    appBar: AppBar(title: const Text('Match Details')),
    body: ListenableBuilder(
      listenable: widget.favorites,
      builder: (_, _) => SportsEventDetailsLayout(
        event: event,
        lite: BrowsingModeSettings.instance.lite,
        status: sportsStatus(event, liveFeed: widget.api.supportsLive),
        date: sportsTime(event.startTimeUtc),
        attribution: widget.api.attribution,
        actions: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton(
              autofocus: true,
              onPressed: matching ? null : findChannels,
              child: const Text('Find Channels'),
            ),
            if (event.homeTeamId != null && event.homeTeamName != null)
              sportsChip(
                '${widget.favorites.teams.containsKey(event.homeTeamId) ? 'Unfollow' : 'Follow'} ${event.homeTeamName}',
                widget.favorites.teams.containsKey(event.homeTeamId),
                () => widget.onFollow(event.homeTeamId!, event.homeTeamName!),
              ),
            if (event.awayTeamId != null && event.awayTeamName != null)
              sportsChip(
                '${widget.favorites.teams.containsKey(event.awayTeamId) ? 'Unfollow' : 'Follow'} ${event.awayTeamName}',
                widget.favorites.teams.containsKey(event.awayTeamId),
                () => widget.onFollow(event.awayTeamId!, event.awayTeamName!),
              ),
            if (event.leagueId != null && event.leagueName != null)
              sportsChip(
                '${widget.favorites.leagues.containsKey(event.leagueId) ? 'Unfollow' : 'Follow'} League',
                widget.favorites.leagues.containsKey(event.leagueId),
                () => widget.onFollow(
                  event.leagueId!,
                  event.leagueName!,
                  league: true,
                ),
              ),
          ],
        ),
        channels: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (matches == null && !matching)
              const Text(
                'Select Find Channels to check available broadcasts.',
                style: TextStyle(fontSize: 13, color: Colors.white60),
              ),
            if (matching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
            if (error != null) Text(error!),
            const SizedBox(height: 24),
            if (matches != null) ...[
              if (!matches!.any(
                (m) => m.confidence == SportsChannelConfidence.verified,
              ))
                const Text('No confirmed channel found for this match.'),
              for (final confidence in [
                SportsChannelConfidence.verified,
                SportsChannelConfidence.possible,
              ]) ...[
                const SizedBox(height: 18),
                Text(switch (confidence) {
                  SportsChannelConfidence.verified => 'EPG-verified Channels',
                  SportsChannelConfidence.possible => 'Possible Channels',
                  SportsChannelConfidence.related => 'Related Sports Channels',
                }, style: const TextStyle(fontSize: 21)),
                for (final m in matches!.where(
                  (m) => m.confidence == confidence,
                ))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SportsChannelTile(
                          channel: m.channel,
                          label: switch (confidence) {
                            SportsChannelConfidence.verified =>
                              'Watch on ${m.channel.name}',
                            SportsChannelConfidence.possible =>
                              'Possible Channel',
                            SportsChannelConfidence.related =>
                              'Browse Sports Channel',
                          },
                          onWatch: () => widget.onWatch(m.channel),
                        ),
                        Text(
                          m.evidence,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
}

class SportsTeamSearchScreen extends StatefulWidget {
  final SportsDataProvider api;
  final SportsFavorites favorites;
  final SportsFollow onFollow;
  const SportsTeamSearchScreen({
    super.key,
    required this.api,
    required this.favorites,
    required this.onFollow,
  });
  @override
  State<SportsTeamSearchScreen> createState() => _SportsTeamSearchScreenState();
}

class _SportsTeamSearchScreenState extends State<SportsTeamSearchScreen> {
  final query = TextEditingController();
  List<SportsTeam> teams = [];
  String? error;
  bool loading = false, searched = false;
  int generation = 0;
  Future<void> search() async {
    final text = query.text.trim();
    if (text.isEmpty) return;
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
      searched = true;
    });
    try {
      final rows = await widget.api.getTeams(text);
      if (mounted && version == generation) setState(() => teams = rows);
    } catch (_) {
      if (mounted && version == generation) {
        setState(() => error = 'Unable to search teams. Please retry.');
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff0a111d),
    appBar: AppBar(title: const Text('Find Teams')),
    body: ListenableBuilder(
      listenable: widget.favorites,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          SizedBox(
            width: 550,
            child: ActivationTextField(
              controller: query,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Team name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => search(),
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: search,
              child: const Text('Search'),
            ),
          ),
          if (widget.api.limitedCoverage)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Free team search is restricted by TheSportsDB (currently Arsenal only). Follow other teams from available match details.',
              ),
            ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (searched && !loading && teams.isEmpty)
            const Text('No matching teams available with this data plan.'),
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton(
                onPressed: () => widget.onFollow(team.id, team.name),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      if (!BrowsingModeSettings.instance.lite) ...[
                        SportsLogo(team.logoUrl),
                        const SizedBox(width: 16),
                      ],
                      Expanded(child: Text(team.name)),
                      Text(
                        widget.favorites.teams.containsKey(team.id)
                            ? 'Unfollow'
                            : 'Follow',
                        style: const TextStyle(color: _blue),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
