import 'artwork_prefetch.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'media_horizontal_rail.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/category_locks.dart';
import '../application/watch_history.dart';
import '../data/tmdb_artwork_service.dart';
import '../data/tmdb_cast_service.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'cinematic_movie_details.dart';
import 'catalog_poster_artwork.dart';
import 'source_rating_badge.dart';
import 'episode_artwork.dart';
import '../data/omdb_ratings_service.dart';
import 'details_screen.dart';
import 'my_list_button.dart';
import 'smooth_page_route.dart';
import 'title_access.dart';

const _blue = Color(0xff64b5f6);
const _background = Color(0xff080d15);
const _secondary = Color(0xffb5bdc9);

/// Uses the provider's ordered episodes and the active profile's existing history.
class CinematicSeriesDetails extends StatefulWidget {
  final IptvProvider provider;
  final MediaDetails info;
  final List<Episode> episodes;
  final bool resolving;
  final Future<void> Function(Episode episode, bool fromBeginning) onPlay;
  final TmdbCastService? castService;
  final TmdbArtworkService? artworkService;
  final OmdbRatingsService? ratingsService;
  const CinematicSeriesDetails({
    super.key,
    required this.provider,
    required this.info,
    required this.episodes,
    required this.resolving,
    required this.onPlay,
    this.castService,
    this.artworkService,
    this.ratingsService,
  });
  @override
  State<CinematicSeriesDetails> createState() => _CinematicSeriesDetailsState();
}

class _CinematicSeriesDetailsState extends State<CinematicSeriesDetails> {
  final playFocus = FocusNode(debugLabel: 'series primary action');
  final pageScroll = ScrollController();
  final seasonsKey = GlobalKey<MediaHorizontalRailState>();
  final episodesKey = GlobalKey<MediaHorizontalRailState>();
  final relatedKey = GlobalKey<MediaHorizontalRailState>();
  final castKey = GlobalKey<MediaHorizontalRailState>();
  late final history = WatchHistory.forProvider(widget.provider);
  final progress = <String, WatchEntry>{};
  List<MovieCredit> credits = [];
  MovieRatings ratings = const MovieRatings();
  List<ContentItem> related = [];
  Uri? logo, backdrop;
  Future<Uri?>? backdropLookup;
  Future<Uri?> fallbackBackdrop() => backdropLookup ??=
      (widget.artworkService ?? TmdbArtworkService.configured).detailsBackdrop(
        info,
      );
  int? season;
  bool initialized = false;
  int revision = 0;
  MediaDetails get info => widget.info;
  late final episodes = List<Episode>.of(widget.episodes)
    ..sort(
      (a, b) => a.season == b.season
          ? a.number.compareTo(b.number)
          : a.season.compareTo(b.season),
    );
  List<int> get seasons => episodes.map((e) => e.season).toSet().toList();
  List<Episode> get visible =>
      episodes.where((e) => e.season == season).toList();
  Episode? get primary {
    final watched = progress.values.toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    if (watched.isEmpty) return episodes.firstOrNull;
    final latest = watched.first;
    final index = episodes.indexWhere((e) => e.id == latest.episode?.id);
    if (index < 0) return episodes.firstOrNull;
    if (!completed(latest)) return episodes[index];
    return index + 1 < episodes.length ? episodes[index + 1] : episodes[index];
  }

  bool completed(WatchEntry? entry) =>
      entry != null &&
      entry.duration > Duration.zero &&
      entry.position.inMilliseconds >= entry.duration.inMilliseconds * .95;
  bool resumable(WatchEntry? entry) =>
      entry != null && !completed(entry) && entry.position > Duration.zero;

  @override
  void initState() {
    super.initState();
    season = seasons.firstOrNull;
    history.addListener(refreshProgress);
    unawaited(refreshProgress());
    unawaited(enrich());
    unawaited(loadRatings());
    unawaited(loadRelated());
  }

  Future<void> refreshProgress() async {
    final request = ++revision;
    final entries = await history.seriesProgress(info.item);
    if (!mounted || request != revision) return;
    setState(() {
      progress
        ..clear()
        ..addEntries(
          entries
              .where((e) => e.episode != null)
              .map((e) => MapEntry(e.episode!.id, e)),
        );
      if (!initialized) {
        season = primary?.season ?? season;
        initialized = true;
      }
    });
  }

  Future<void> loadRatings() async {
    final value = await (widget.ratingsService ?? OmdbRatingsService.configured)
        .ratings(info);
    if (mounted) setState(() => ratings = value);
  }

  Future<void> enrich() async {
    final client = widget.castService ?? TmdbCastService.configured;
    final artwork = widget.artworkService ?? TmdbArtworkService.configured;
    // Independent enrichment never blocks the episode browser.
    await Future.wait([
      () async {
        final value = await artwork.titleLogo(info);
        if (mounted) setState(() => logo = value);
      }(),
      () async {
        final value = await client.credits(info);
        if (mounted) {
          ArtworkPrefetch.images(
            context,
            value.map((person) => person.photo),
            width: 252,
            limit: 6,
          );
          setState(() => credits = value);
        }
      }(),
      if (info.backdrop == null)
        () async {
          final value = await fallbackBackdrop();
          if (mounted) setState(() => backdrop = value);
        }(),
    ]);
  }

  Future<void> loadRelated() async {
    if (info.item.categoryId == null) return;
    try {
      // Provider categories are the existing related-title source. Never recommend
      // external TMDB shows that cannot be played by this account.
      final items = await widget.provider.getItems(
        Category(info.item.categoryId!, '', ContentType.series),
      );
      final locks = CategoryLocks.forProvider(widget.provider);
      await locks.load();
      final seen = <String>{info.item.id};
      final result = items
          .where(
            (item) =>
                item.type == ContentType.series &&
                seen.add(item.id) &&
                locks.allowsItem(item) &&
                !locks.titleHidden(item) &&
                !locks.titleConfigured(item) &&
                (item.categoryId == null ||
                    !locks.hidden(Category(item.categoryId!, '', item.type)) &&
                        !locks.configured(
                          Category(item.categoryId!, '', item.type),
                        )),
          )
          .take(12)
          .toList();
      if (mounted) setState(() => related = result);
    } catch (_) {
      /* Optional recommendations must not block episodes. */
    }
  }

  @override
  void dispose() {
    history.removeListener(refreshProgress);
    playFocus.dispose();
    pageScroll.dispose();
    super.dispose();
  }

  void focusPlay() {
    playFocus.requestFocus();
    final ctx = playFocus.context;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          alignment: .35,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void focusSeasons() {
    if (seasons.isEmpty) {
      belowEpisodes();
    } else {
      seasonsKey.currentState?.focusCurrent();
    }
  }

  void focusEpisodes() {
    if (visible.isEmpty) {
      focusPlay();
    } else {
      episodesKey.currentState?.focusCurrent();
    }
  }

  void belowEpisodes() {
    if (related.isNotEmpty) {
      relatedKey.currentState?.focusCurrent();
    }
  }

  List<MovieCredit> get people => credits.isNotEmpty
      ? credits
      : [
          for (final name
              in info.cast
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty))
            MovieCredit(name, 'Cast'),
          if (info.director.trim().isNotEmpty)
            MovieCredit(info.director, 'Director / Creator'),
        ];
  Future<void> playEpisode(Episode episode, bool restart) async {
    if (widget.resolving) return;
    final restorePrimary = playFocus.hasFocus;
    await widget.onPlay(episode, restart);
    if (mounted) {
      await refreshProgress();
      if (restorePrimary) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) focusPlay();
        });
      }
    }
  }

  Future<void> playCard(Episode episode, FocusNode node) async {
    final before = node.context?.findRenderObject();
    final top = before is RenderBox
        ? before.localToGlobal(Offset.zero).dy
        : null;
    await playEpisode(episode, false);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      final after = node.context?.findRenderObject();
      // Resume information can add height above the row. Compensate for that
      // layout change so returning from playback keeps the episode in place.
      if (top != null && after is RenderBox && pageScroll.hasClients) {
        final delta = after.localToGlobal(Offset.zero).dy - top;
        pageScroll.jumpTo(
          (pageScroll.offset + delta).clamp(
            0,
            pageScroll.position.maxScrollExtent,
          ),
        );
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void moreInfo([Episode? episode]) {
    final entry = episode == null ? null : progress[episode.id];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          episode == null
              ? movieDisplayTitle(info.item.name)
              : 'S${episode.season} E${episode.number} \u00b7 ${episode.title}',
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Text(
              [
                episode == null ? info.synopsis : episode.synopsis,
                if (episode == null) ...[
                  if (info.releaseDate.isNotEmpty)
                    'Released: ${info.releaseDate}',
                  if (info.genre.isNotEmpty) 'Genres: ${info.genre}',
                  if (info.ageRating.isNotEmpty)
                    'Age rating: ${info.ageRating}',
                  if (info.language.isNotEmpty) 'Language: ${info.language}',
                  if (info.director.isNotEmpty)
                    'Director / Creator: ${info.director}',
                  if (info.cast.isNotEmpty) 'Cast: ${info.cast}',
                ] else ...[
                  if (episode.duration.isNotEmpty)
                    movieDisplayDuration(episode.duration),
                  if (episode.airDate.isNotEmpty)
                    'Air date: ${episode.airDate}',
                  if (completed(entry))
                    'Watched'
                  else if (resumable(entry))
                    '${((entry!.duration - entry.position).inSeconds / 60).ceil()} min left',
                ],
              ].where((s) => s.isNotEmpty).join('\n\n'),
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> trailer() async {
    try {
      if (!await launchUrl(
            info.trailer!,
            mode: LaunchMode.externalApplication,
          ) &&
          mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open trailer.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to open trailer.')),
        );
      }
    }
  }

  ButtonStyle secondaryStyle(double scale) =>
      TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xc0202833),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: TextStyle(fontSize: 19 * scale, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: const BorderSide(color: Colors.white24),
      ).copyWith(
        animationDuration: const Duration(milliseconds: 170),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? _blue
                : Colors.white24,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? const Color(0x3364b5f6)
              : Colors.white10,
        ),
      );
  Widget heading(String text, double scale) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 10),
    child: Text(
      text,
      style: TextStyle(fontSize: 28 * scale, fontWeight: FontWeight.w500),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 1920).clamp(.62, 1.15);
    final target = primary;
    final saved = target == null ? null : progress[target.id];
    final resume = resumable(saved);
    final image = info.backdrop ?? backdrop;
    final title = Text(
      movieDisplayTitle(info.item.name),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 46 * scale,
        height: 1.1,
        fontWeight: FontWeight.w600,
      ),
    );
    final activeEpisodes = visible;
    final cardWidth = (290 * scale).clamp(220.0, 334.0);
    return ColoredBox(
      color: _background,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
        child: Stack(
          children: [
            if (image != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size.height * .88,
                child: CachedNetworkImage(
                  imageUrl: image.toString(),
                  fit: BoxFit.cover,
                  alignment: Alignment.topRight,
                  memCacheWidth: 1920,
                  placeholder: (_, _) => const SizedBox(),
                  errorWidget: (_, _, _) => FutureBuilder<Uri?>(
                    future: fallbackBackdrop(),
                    builder: (context, snapshot) =>
                        snapshot.data == null || snapshot.data == image
                        ? const SizedBox()
                        : CachedNetworkImage(
                            imageUrl: snapshot.data.toString(),
                            fit: BoxFit.cover,
                            alignment: Alignment.topRight,
                            memCacheWidth: 1920,
                            errorWidget: (_, _, _) => const SizedBox(),
                          ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _background,
                        const Color(0xee080d15),
                        const Color(0x22080d15),
                      ],
                      stops: const [0, .38, 1],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.transparent, _background],
                      stops: const [.25, .9],
                    ),
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              key: PageStorageKey('series-details-${info.item.id}'),
              controller: pageScroll,
              padding: EdgeInsets.fromLTRB(
                size.width * .045,
                56,
                size.width * .045,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: size.width < 700
                        ? size.width * .87
                        : size.width * .49,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (logo == null)
                          title
                        else
                          Semantics(
                            label: movieDisplayTitle(info.item.name),
                            image: true,
                            child: CachedNetworkImage(
                              imageUrl: logo.toString(),
                              width: 500 * scale,
                              height: 120 * scale,
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              memCacheWidth: 1000,
                              placeholder: (_, _) => title,
                              errorWidget: (_, _, _) => title,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          [
                            TmdbCastService.configured.year(info) ?? '',
                            if (seasons.isNotEmpty)
                              '${seasons.length} ${seasons.length == 1 ? 'Season' : 'Seasons'}',
                            info.genre,
                            info.ageRating,
                          ].where((s) => s.isNotEmpty).join(' \u00b7 '),
                          style: TextStyle(
                            fontSize: 18 * scale,
                            color: _secondary,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 6,
                            children: [
                              SourceRatingBadge(
                                source: 'IMDb',
                                asset: 'assets/branding/imdb.svg',
                                value: ratings.imdb,
                                scale: scale,
                              ),
                              SourceRatingBadge(
                                source: 'Rotten Tomatoes',
                                asset: 'assets/branding/rotten_tomatoes.svg',
                                value: ratings.rottenTomatoes,
                                scale: scale,
                              ),
                            ],
                          ),
                        ),
                        if (ratings.isEmpty && info.rating.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              movieDisplayRating(info.rating),
                              style: TextStyle(
                                fontSize: 18 * scale,
                                color: _secondary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 650 * scale),
                          child: Text(
                            info.synopsis.isEmpty
                                ? 'No synopsis available.'
                                : info.synopsis,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20 * scale,
                              height: 1.4,
                              color: _secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Focus(
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent || event is KeyRepeatEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          if (people.isNotEmpty) {
                            castKey.currentState?.focusCurrent();
                          } else {
                            focusSeasons();
                          }
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilledButton.icon(
                            focusNode: playFocus,
                            autofocus: true,
                            onPressed: target == null || widget.resolving
                                ? null
                                : () => playEpisode(target, false),
                            style:
                                FilledButton.styleFrom(
                                  backgroundColor: const Color(0xfff2f4f7),
                                  foregroundColor: const Color(0xff10151c),
                                  minimumSize: const Size(0, 44),
                                  textStyle: TextStyle(
                                    fontSize: 20 * scale,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  side: const BorderSide(
                                    color: _blue,
                                    width: 2,
                                  ),
                                ).copyWith(
                                  animationDuration: const Duration(
                                    milliseconds: 170,
                                  ),
                                ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              widget.resolving
                                  ? 'Preparing...'
                                  : target == null
                                  ? 'Play'
                                  : '${resume ? 'Resume' : 'Play'} S${target.season} E${target.number}',
                            ),
                          ),
                          const SizedBox(width: 8),
                          MyListButton(
                            provider: widget.provider,
                            item: info.item,
                            showLabel: true,
                            style: secondaryStyle(scale),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            style: secondaryStyle(scale),
                            onPressed: moreInfo,
                            icon: const Icon(Icons.info_outline),
                            label: const Text('More Info'),
                          ),
                          if (info.trailer != null) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              style: secondaryStyle(scale),
                              onPressed: trailer,
                              icon: const Icon(Icons.play_arrow_outlined),
                              label: const Text('Trailer'),
                            ),
                          ],
                          if (resume) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              style: secondaryStyle(scale),
                              onPressed: widget.resolving
                                  ? null
                                  : () => playEpisode(target!, true),
                              icon: const Icon(Icons.replay),
                              label: const Text('Play from beginning'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (resume)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 280 * scale,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearProgressIndicator(
                              value:
                                  (saved!.position.inMilliseconds /
                                          saved.duration.inMilliseconds)
                                      .clamp(0, 1),
                              minHeight: 3,
                              color: _blue,
                              backgroundColor: Colors.white24,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${((saved.duration - saved.position).inSeconds / 60).ceil()} min left',
                              style: TextStyle(
                                fontSize: 16 * scale,
                                color: _secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (people.isNotEmpty) ...[
                    heading('Cast & Crew', scale),
                    MediaHorizontalRail(
                      key: castKey,
                      count: people.length,
                      width: 144,
                      height: 150,
                      up: focusPlay,
                      down: focusSeasons,
                      itemBuilder: (index, node) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: CastCreditCard(
                          credit: people[index],
                          focusNode: node,
                        ),
                      ),
                    ),
                  ],
                  if (seasons.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: Text('No episodes available'),
                    )
                  else ...[
                    const SizedBox(height: 18),
                    MediaHorizontalRail(
                      key: seasonsKey,
                      count: seasons.length,
                      width: 220 * scale + 12,
                      height: 42,
                      up: () => people.isEmpty
                          ? focusPlay()
                          : castKey.currentState?.focusCurrent(),
                      down: focusEpisodes,
                      initialIndex: seasons
                          .indexOf(season!)
                          .clamp(0, seasons.length - 1),
                      itemBuilder: (index, node) => Padding(
                        padding: const EdgeInsets.only(right: 10, bottom: 6),
                        child: TextButton(
                          focusNode: node,
                          style: secondaryStyle(scale).copyWith(
                            minimumSize: const WidgetStatePropertyAll(
                              Size(0, 34),
                            ),
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(horizontal: 20),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: WidgetStatePropertyAll(
                              seasons[index] == season
                                  ? const Color(0xff245d88)
                                  : const Color(0xff202833),
                            ),
                          ),
                          onPressed: () =>
                              setState(() => season = seasons[index]),
                          child: Text(
                            seasons[index] == 0
                                ? 'Specials'
                                : 'Season ${seasons[index]}',
                          ),
                        ),
                      ),
                    ),
                    MediaHorizontalRail(
                      key: episodesKey,
                      contentKey: season,
                      count: activeEpisodes.length,
                      width: cardWidth + 18,
                      height: cardWidth * 9 / 16 + 130 * scale + 22,
                      initialIndex: activeEpisodes
                          .indexWhere((e) => e.id == target?.id)
                          .clamp(0, activeEpisodes.length - 1),
                      up: focusSeasons,
                      down: belowEpisodes,
                      itemBuilder: (index, node) => Padding(
                        padding: const EdgeInsets.fromLTRB(4, 5, 14, 8),
                        child: _EpisodeCard(
                          episode: activeEpisodes[index],
                          info: info,
                          artworkService: widget.artworkService,
                          fallback: info.backdrop ?? backdrop,
                          entry: progress[activeEpisodes[index].id],
                          focusNode: node,
                          scale: scale,
                          onInfo: () => moreInfo(activeEpisodes[index]),
                          onPlay: () => playCard(activeEpisodes[index], node),
                        ),
                      ),
                    ),
                  ],
                  if (related.isNotEmpty) ...[
                    heading('More Like This', scale),
                    MediaHorizontalRail(
                      key: relatedKey,
                      count: related.length,
                      width: 154 * scale + 18,
                      height: 250 * scale + 40,
                      up: focusEpisodes,
                      down: () {},
                      itemBuilder: (index, node) => Padding(
                        padding: const EdgeInsets.only(right: 18, bottom: 8),
                        child: _RelatedSeries(
                          item: related[index],
                          provider: widget.provider,
                          artworkService: widget.artworkService,
                          focusNode: node,
                          onPressed: () async {
                            if (!await requestTitleAccess(
                                  context,
                                  widget.provider,
                                  related[index],
                                ) ||
                                !context.mounted) {
                              return;
                            }
                            await Navigator.of(context).push(
                              SmoothPageRoute(
                                builder: (_) => DetailsScreen(
                                  provider: widget.provider,
                                  item: related[index],
                                ),
                              ),
                            );
                            if (mounted) node.requestFocus();
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final MediaDetails info;
  final TmdbArtworkService? artworkService;
  final Uri? fallback;
  final WatchEntry? entry;
  final FocusNode focusNode;
  final double scale;
  final Future<void> Function() onPlay;
  final VoidCallback onInfo;
  const _EpisodeCard({
    required this.episode,
    required this.info,
    this.artworkService,
    required this.fallback,
    required this.entry,
    required this.focusNode,
    required this.scale,
    required this.onPlay,
    required this.onInfo,
  });
  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.contextMenu) {
        onInfo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TextButton(
      key: ValueKey('series-episode-${episode.id}'),
      focusNode: focusNode,
      onPressed: onPlay,
      onLongPress: onInfo,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          final fraction = entry == null || entry!.duration <= Duration.zero
              ? 0.0
              : (entry!.position.inMilliseconds /
                        entry!.duration.inMilliseconds)
                    .clamp(0.0, 1.0);
          return AnimatedScale(
            scale: focused ? 1.04 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: focused
                    ? const Color(0xff29394b)
                    : const Color(0xff202833),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: focused ? _blue : Colors.transparent,
                  width: 3,
                ),
                boxShadow: focused
                    ? const [BoxShadow(color: Colors.black26, blurRadius: 6)]
                    : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EpisodeArtwork(
                            info: info,
                            episode: episode,
                            backdrop: fallback,
                            service: artworkService,
                          ),
                          if (episode.duration.isNotEmpty)
                            Positioned(
                              right: 6,
                              bottom: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    movieDisplayDuration(episode.duration),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                          if (fraction >= .95)
                            const Positioned(
                              top: 6,
                              right: 6,
                              child: Tooltip(
                                message: 'Watched',
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          if (fraction > 0)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: fraction,
                                minHeight: 3,
                                color: _blue,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${episode.number}. ${episode.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18 * scale,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Text(
                              episode.synopsis,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16 * scale,
                                color: _secondary,
                              ),
                            ),
                          ),
                          if (fraction > 0 && fraction < .95)
                            Text(
                              'Resume \u00b7 ${((entry!.duration - entry!.position).inSeconds / 60).ceil()} min left',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14 * scale,
                                color: _blue,
                              ),
                            ),
                        ],
                      ),
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

class _RelatedSeries extends StatelessWidget {
  final ContentItem item;
  final IptvProvider provider;
  final TmdbArtworkService? artworkService;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  const _RelatedSeries({
    required this.item,
    required this.provider,
    this.artworkService,
    required this.focusNode,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => TextButton(
    focusNode: focusNode,
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.all(3),
      foregroundColor: Colors.white,
    ),
    child: Builder(
      builder: (context) => AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Focus.of(context).hasFocus ? _blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CatalogPosterArtwork(
                  item: item,
                  provider: provider,
                  service: artworkService,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(5),
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A static skeleton avoids unnecessary animation while the API is busy.
class SeriesDetailsSkeleton extends StatelessWidget {
  const SeriesDetailsSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading series details',
    child: ColoredBox(
      color: _background,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Container(width: 300, height: 48, color: const Color(0xff202833)),
            const SizedBox(height: 16),
            Container(width: 420, height: 18, color: const Color(0xff202833)),
            const SizedBox(height: 16),
            Container(width: 420, height: 60, color: const Color(0xff151d28)),
            const SizedBox(height: 20),
            Container(width: 180, height: 44, color: const Color(0xff202833)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: 18),
                itemBuilder: (_, _) =>
                    Container(width: 220, color: const Color(0xff151d28)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
