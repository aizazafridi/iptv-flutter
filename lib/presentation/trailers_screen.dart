import 'cinematic_movie_details.dart' show CastCreditCard;
import '../data/tmdb_cast_service.dart' show MovieCredit;
import 'reminder_controls.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../application/browsing_mode.dart';
import '../application/category_locks.dart';
import '../application/trailer_reminders.dart';
import '../application/trailer_catalog_match.dart';
import '../data/trailers_repository.dart';
import '../data/artwork_repository.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../domain/trailer_movie.dart';
import 'shared_artwork_image.dart';
import 'media_horizontal_rail.dart';
import 'trailer_screen.dart';
import 'details_screen.dart';
import 'smooth_page_route.dart';

class TrailersScreen extends StatefulWidget {
  final VoidCallback? onNavigation;
  final IptvProvider provider;
  final TrailersRepository? repository;
  final TrailerReminders? reminders;
  const TrailersScreen({
    super.key,
    required this.provider,
    this.repository,
    this.reminders,
    this.onNavigation,
  });
  @override
  State<TrailersScreen> createState() => TrailersScreenState();
}

class TrailersScreenState extends State<TrailersScreen> {
  void focusEntry() {
    for (final rail in rails) {
      if (rail.currentState != null) {
        rail.currentState!.focusCurrent();
        return;
      }
    }
    back.requestFocus();
  }

  late final repo = widget.repository ?? TrailersRepository.configured;
  late final reminders =
      widget.reminders ?? TrailerReminders.forProvider(widget.provider);
  final sections = <TrailerCollection, TrailerPage>{},
      errors = <TrailerCollection, String>{};
  final rails = List.generate(
    TrailerCollection.values.length + 1,
    (_) => GlobalKey<MediaHorizontalRailState>(),
  );
  final viewNodes = List.generate(
    TrailerCollection.values.length + 1,
    (i) => FocusNode(debugLabel: 'trailers view all $i'),
  );
  final back = FocusNode(debugLabel: 'trailers back');
  Timer? debounce;
  TrailerMovie? featured;
  bool started = false, restricted = false;
  String? reminderError;
  int selection = 0;
  bool get lite => BrowsingModeSettings.instance.lite;
  @override
  void initState() {
    super.initState();
    reminders.addListener(changed);
    BrowsingModeSettings.instance.addListener(changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      final locale = Localizations.localeOf(context);
      repo.locale(locale.toLanguageTag(), locale.countryCode);
      unawaited(load());
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    final locks = CategoryLocks.forProvider(widget.provider);
    await locks.load();
    if (!mounted) return;
    if (locks.kidsProfile) {
      setState(() => restricted = true);
      return;
    }
    unawaited(
      reminders.load().catchError((Object _) {
        if (mounted) {
          setState(
            () => reminderError = 'Saved reminders could not be loaded.',
          );
        }
      }),
    );
    for (final c in TrailerCollection.values) {
      unawaited(loadSection(c));
    }
  }

  Future<void> loadSection(TrailerCollection c, {bool refresh = false}) async {
    setState(() {
      errors.remove(c);
    });
    try {
      final page = await repo.page(c, refresh: refresh);
      if (!mounted) return;
      setState(() => sections[c] = page);
      if (featured == null && page.movies.isNotEmpty) {
        select(page.movies.first, immediate: true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => errors[c] = e is TrailerDiscoveryError
              ? e.message
              : 'This collection could not be loaded.',
        );
      }
    }
  }

  void select(TrailerMovie movie, {bool immediate = false}) {
    debounce?.cancel();
    if (featured?.id == movie.id) return;
    final ticket = ++selection;
    void apply() {
      if (!mounted) return;
      setState(() {
        featured = movie;
      });
      unawaited(() async {
        try {
          final info = await repo.details(movie.id);
          if (mounted && ticket == selection) {
            setState(() {
              featured = info;
            });
          }
        } catch (_) {
          // Keep the collection metadata; opening the title offers retry.
        }
      }());
    }

    if (immediate) {
      apply();
    } else {
      debounce = Timer(const Duration(milliseconds: 170), apply);
    }
  }

  Future<void> openDetails(TrailerMovie movie) async {
    final focus = FocusManager.instance.primaryFocus;
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => TrailerMovieDetailsScreen(
          provider: widget.provider,
          movie: movie,
          repository: repo,
          reminders: reminders,
        ),
      ),
    );
    if (mounted && focus?.context != null) focus!.requestFocus();
  }

  void heroFocus() => back.requestFocus();

  List<
    ({
      String title,
      List<TrailerMovie>? movies,
      TrailerCollection? collection,
      String? error,
      bool stale,
    })
  >
  get rows => [
    for (final c in TrailerCollection.values)
      (
        title: c.label,
        movies: sections[c]?.movies,
        collection: c,
        error: errors[c],
        stale: sections[c]?.stale ?? false,
      ),
    (
      title: 'Reminders',
      movies: reminders.items,
      collection: null,
      error: null,
      stale: false,
    ),
  ];
  @override
  void dispose() {
    debounce?.cancel();
    reminders.removeListener(changed);
    BrowsingModeSettings.instance.removeListener(changed);
    for (final node in [...viewNodes, back]) {
      node.dispose();
    }
    super.dispose();
  }

  Widget hero(double height) {
    final movie = featured;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!lite && movie?.backdrop != null)
            SharedArtworkImage(
              key: ValueKey('trailer-hero:${movie!.id}'),
              imageUrl: movie.backdrop.toString(),
              kind: ArtworkKind.backdrop,
              fit: BoxFit.cover,
            ),
          if (!lite)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xff08111c),
                    Color(0xd908111c),
                    Color(0x2208111c),
                  ],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          if (!lite)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xff08111c)],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: LayoutBuilder(
              builder: (context, size) => Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'COMING SOON & MOVIE TRAILERS',
                          style: TextStyle(
                            color: Color(0xff64b5f6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movie?.title ?? 'Discover your next movie',
                          key: const ValueKey('trailers-hero-title'),
                          maxLines: height < 260 ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: size.maxWidth > 1200 ? 34 : 26,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (movie != null)
                          Text(
                            [
                              movie.dateLabel,
                              if (movie.certification.isNotEmpty)
                                movie.certification,
                              if (movie.genres.isNotEmpty)
                                movie.genres.take(2).join(' · '),
                              if (movie.rating > 0)
                                '★ ${movie.rating.toStringAsFixed(1)}/10',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          movie?.overview.isNotEmpty == true
                              ? movie!.overview
                              : 'Watch trailers for upcoming releases, popular movies and films in theaters.',
                          maxLines: lite || height < 260 ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget row(
    int index, {
    required double cardWidth,
    required double cardHeight,
  }) {
    final row = rows[index];
    final movies = row.movies;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (row.collection != null)
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      rails[index].currentState?.focusCurrent();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      index == 0
                          ? heroFocus()
                          : rails[index - 1].currentState?.focusCurrent();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextButton(
                    focusNode: viewNodes[index],
                    onPressed: () => Navigator.of(context).push(
                      SmoothPageRoute<void>(
                        builder: (_) => TrailerCollectionScreen(
                          provider: widget.provider,
                          collection: row.collection!,
                          repository: repo,
                          reminders: reminders,
                        ),
                      ),
                    ),
                    child: const Text('View All ›'),
                  ),
                ),
            ],
          ),
          if (row.stale)
            const Text(
              'Showing cached movies',
              style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
            ),
          if (row.error != null)
            TextButton(
              onPressed: () => loadSection(row.collection!, refresh: true),
              child: Text('${row.error} Retry'),
            )
          else if (movies == null)
            const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (movies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No movies available in this collection.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            MediaHorizontalRail(
              key: rails[index],
              count: movies.length,
              width: cardWidth,
              height: cardHeight,
              contentKey: 'trailers:${row.title}',
              up: () => index == 0
                  ? heroFocus()
                  : rails[index - 1].currentState?.focusCurrent(),
              down: () => index + 1 < rows.length
                  ? rails[index + 1].currentState?.focusCurrent()
                  : heroFocus(),
              onLeftBoundary: widget.onNavigation ?? back.requestFocus,
              onRightBoundary: row.collection == null
                  ? null
                  : () => viewNodes[index].requestFocus(),
              itemBuilder: (i, node) => TrailerDiscoveryCard(
                movie: movies[i],
                focusNode: node,
                lite: lite,
                autofocus: index == 0 && i == 0,
                onFocused: () => select(movies[i]),
                onOpen: () => openDetails(movies[i]),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff08111c),
    appBar: AppBar(
      backgroundColor: const Color(0xff08111c),
      leading: IconButton(
        focusNode: back,
        onPressed: widget.onNavigation ?? () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('Trailers', style: TextStyle(fontSize: 22)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Center(
            child: Text(
              '${repo.language} · ${repo.region}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ),
        ),
      ],
    ),
    body: restricted
        ? const Center(
            child: Text(
              'Trailers discovery is not available in Kids profiles.',
            ),
          )
        : LayoutBuilder(
            builder: (context, size) {
              final width = (size.maxWidth / 5).clamp(176.0, 270.0);
              final height = lite ? 82.0 : (width * .56 + 40);
              return Column(
                children: [
                  hero((size.maxHeight * .43).clamp(225.0, 330.0)),
                  Expanded(
                    child: ListView(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          row(i, cardWidth: width, cardHeight: height),
                        if (reminderError != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(reminderError!),
                          ),
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Movie data: TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.\nReminders are checked when you open or resume the app and when your movie catalog refreshes.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
  );
}

class TrailerDiscoveryCard extends StatelessWidget {
  final TrailerMovie movie;
  final FocusNode? focusNode;
  final bool lite, autofocus;
  final VoidCallback onFocused, onOpen;
  const TrailerDiscoveryCard({
    super.key,
    required this.movie,
    this.focusNode,
    required this.lite,
    this.autofocus = false,
    required this.onFocused,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Focus(
      canRequestFocus: false,
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedScale(
            scale: focused && !lite ? 1.06 : 1,
            duration: Duration(milliseconds: lite ? 0 : 170),
            curve: Curves.easeOutCubic,
            child: TextButton(
              focusNode: focusNode,
              autofocus: autofocus,
              onFocusChange: (value) {
                if (value) onFocused();
              },
              onPressed: onOpen,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xff182435),
                elevation: focused && !lite ? 5 : 0,
                shadowColor: const Color(0x8864b5f6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: focused ? const Color(0xff64b5f6) : Colors.white12,
                    width: focused ? 2 : 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!lite)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(9),
                        ),
                        child: movie.card == null
                            ? const ColoredBox(
                                color: Color(0xff1c2b3d),
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: Colors.white38,
                                ),
                              )
                            : SharedArtworkImage(
                                imageUrl: movie.card.toString(),
                                kind: ArtworkKind.episode,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 5, 10, 2),
                    child: Text(
                      movie.title,
                      maxLines: lite ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
                    child: Text(
                      movie.dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
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

class TrailerMovieDetailsScreen extends StatefulWidget {
  final IptvProvider provider;
  final TrailerMovie movie;
  final TrailersRepository repository;
  final TrailerReminders reminders;
  const TrailerMovieDetailsScreen({
    super.key,
    required this.provider,
    required this.movie,
    required this.repository,
    required this.reminders,
  });
  @override
  State<TrailerMovieDetailsScreen> createState() =>
      _TrailerMovieDetailsScreenState();
}

class _TrailerMovieDetailsScreenState extends State<TrailerMovieDetailsScreen> {
  late TrailerMovie movie = widget.movie;
  String? error, matchError;
  bool loading = true, saving = false;
  List<ContentItem>? matches;
  @override
  void initState() {
    super.initState();
    widget.reminders.addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    actionFocus.dispose();
    backFocus.dispose();
    widget.reminders.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool refresh = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final info = await widget.repository.details(movie.id, refresh: refresh);
      if (mounted) setState(() => movie = info);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is TrailerDiscoveryError
              ? e.message
              : 'Movie details could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
    await checkMatches();
  }

  Future<void> checkMatches() async {
    if (mounted) {
      setState(() {
        matches = null;
        matchError = null;
      });
    }
    try {
      final items = await matchTrailerMovie(widget.provider, movie);
      if (mounted) setState(() => matches = items);
    } catch (_) {
      if (mounted) {
        setState(() {
          matches = [];
          matchError = 'Your IPTV catalog could not be checked.';
        });
      }
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await editTrailerReminder(context, widget.reminders, movie);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder could not be saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  final actionFocus = FocusNode(debugLabel: 'trailer details action');
  final backFocus = FocusNode(debugLabel: 'trailer details back');
  final castRail = GlobalKey<MediaHorizontalRailState>();

  @override
  Widget build(BuildContext context) {
    final lite = BrowsingModeSettings.instance.lite;
    final size = MediaQuery.sizeOf(context);
    final scale = (size.width / 1920).clamp(.62, 1.0);
    final buttonStyle = reminderButtonStyle().copyWith(
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 19 * scale, fontWeight: FontWeight.w500),
      ),
      overlayColor: const WidgetStatePropertyAll(Color(0x66529cff)),
    );
    return Scaffold(
      backgroundColor: const Color(0xff090b10),
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!lite && movie.backdrop != null)
              Positioned(
                top: 0,
                right: 0,
                width: size.width * .76,
                height: size.height * .86,
                child: SharedArtworkImage(
                  imageUrl: movie.backdrop.toString(),
                  kind: ArtworkKind.backdrop,
                  fit: BoxFit.cover,
                  alignment: Alignment.topRight,
                ),
              ),
            if (!lite) ...[
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xff090b10),
                        Color(0xf0090b10),
                        Color(0x33090b10),
                      ],
                      stops: [0, .36, 1],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xff090b10)],
                      stops: [.3, .94],
                    ),
                  ),
                ),
              ),
            ],
            SingleChildScrollView(
              key: const ValueKey('trailer-cinematic-details'),
              padding: EdgeInsets.fromLTRB(
                size.width * .045,
                56,
                size.width * .045,
                40,
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
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 46 * scale,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          [
                            movie.dateLabel,
                            if (movie.runtime > 0)
                              '${movie.runtime ~/ 60}h ${movie.runtime % 60}m',
                            ...movie.genres.take(2),
                            if (movie.certification.isNotEmpty)
                              movie.certification,
                          ].join(' \u00b7 '),
                          style: TextStyle(
                            fontSize: 16.5 * scale,
                            color: const Color(0xffb7bcc6),
                          ),
                        ),
                        if (movie.rating > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 9),
                            child: Text(
                              'TMDB  ${movie.rating.toStringAsFixed(1)}/10',
                              style: TextStyle(
                                fontSize: 18 * scale,
                                color: const Color(0xfff4cb65),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Text(
                          movie.overview.isEmpty
                              ? 'No synopsis available.'
                              : movie.overview,
                          key: const ValueKey('trailer-details-synopsis'),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20 * scale,
                            height: 1.4,
                            color: const Color(0xffb7bcc6),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        backFocus.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                          movie.cast.isNotEmpty &&
                          !lite) {
                        castRail.currentState?.focusCurrent();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (movie.video != null)
                          FilledButton.icon(
                            key: const ValueKey('discovery-details-watch'),
                            focusNode: actionFocus,
                            autofocus: true,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(0, 42),
                              textStyle: TextStyle(
                                fontSize: 19 * scale,
                                fontWeight: FontWeight.w500,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            onPressed: () => openInAppTrailer(
                              context,
                              movie.video!.uri,
                              title: movie.title,
                              allowExternalFallback: true,
                            ),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Watch Trailer'),
                          ),
                        TextButton.icon(
                          key: const ValueKey('discovery-details-reminder'),
                          focusNode: movie.video == null ? actionFocus : null,
                          autofocus: movie.video == null,
                          style: buttonStyle,
                          onPressed: saving ? null : save,
                          icon: Icon(
                            widget.reminders.contains(movie.id)
                                ? Icons.check
                                : Icons.add,
                          ),
                          label: Text(
                            widget.reminders.contains(movie.id)
                                ? 'Reminder Set'
                                : 'Remind Me',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Loading trailer details...',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (!loading && error == null && movie.video == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'No trailer loaded for this title.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (error != null)
                    TextButton(
                      onPressed: () => load(refresh: true),
                      child: Text('$error Retry'),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 12),
                    child: Text(
                      'Cast & Crew',
                      style: TextStyle(
                        fontSize: 29 * scale,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (movie.cast.isEmpty)
                    Text(
                      loading
                          ? 'Loading cast information...'
                          : error != null
                          ? 'Cast could not be loaded. Retry movie details above.'
                          : 'Cast information is not available yet.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    )
                  else if (lite)
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        for (final person in movie.cast)
                          Text(
                            '${person.name} \u00b7 ${person.character}',
                            style: const TextStyle(fontSize: 13),
                          ),
                      ],
                    )
                  else
                    SizedBox(
                      height: 150,
                      child: MediaHorizontalRail(
                        key: castRail,
                        count: movie.cast.length,
                        width: 144,
                        height: 150,
                        up: actionFocus.requestFocus,
                        down: () {},
                        itemBuilder: (index, node) {
                          final person = movie.cast[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: CastCreditCard(
                              focusNode: node,
                              credit: MovieCredit(
                                person.name,
                                person.character,
                                TrailerMovie.image(person.profilePath, 'w185'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (matches == null)
                    const Text(
                      'Checking your IPTV catalog...',
                      style: TextStyle(fontSize: 12),
                    )
                  else if (matchError != null)
                    TextButton(
                      onPressed: checkMatches,
                      child: Text('$matchError Retry'),
                    )
                  else if (matches!.isEmpty)
                    const Text(
                      "No confirmed match found in this profile's IPTV catalog.",
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    )
                  else ...[
                    Text(
                      'Available in My IPTV',
                      style: TextStyle(fontSize: 24 * scale),
                    ),
                    for (final item in matches!)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          SmoothPageRoute<void>(
                            builder: (_) => DetailsScreen(
                              provider: widget.provider,
                              item: item,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.movie_outlined),
                        label: Text(item.name),
                      ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: Focus(
                canRequestFocus: false,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    actionFocus.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: IconButton(
                  focusNode: backFocus,
                  tooltip: 'Back',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrailerCollectionScreen extends StatefulWidget {
  final IptvProvider provider;
  final TrailerCollection collection;
  final TrailersRepository repository;
  final TrailerReminders reminders;
  const TrailerCollectionScreen({
    super.key,
    required this.provider,
    required this.collection,
    required this.repository,
    required this.reminders,
  });
  @override
  State<TrailerCollectionScreen> createState() =>
      _TrailerCollectionScreenState();
}

class _TrailerCollectionScreenState extends State<TrailerCollectionScreen> {
  final movies = <TrailerMovie>[];
  int page = 0, total = 1;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(more());
  }

  Future<void> more() async {
    if (loading || page >= total) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.repository.page(
        widget.collection,
        page: page + 1,
      );
      if (mounted) {
        setState(() {
          final ids = movies.map((m) => m.id).toSet();
          movies.addAll(next.movies.where((m) => ids.add(m.id)));
          page = next.page;
          total = next.totalPages;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is TrailerDiscoveryError
              ? e.message
              : 'This page could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lite = BrowsingModeSettings.instance.lite;
    return Scaffold(
      backgroundColor: const Color(0xff08111c),
      appBar: AppBar(title: Text(widget.collection.label)),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              scrollCacheExtent: const ScrollCacheExtent.pixels(500),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: lite ? 450 : 320,
                childAspectRatio: lite ? 4 : 1.65,
              ),
              itemCount: movies.length,
              itemBuilder: (context, index) {
                final movie = movies[index];
                return TrailerDiscoveryCard(
                  movie: movie,
                  lite: lite,
                  autofocus: index == 0,
                  onFocused: () {},
                  onOpen: () {
                    Navigator.of(context).push(
                      SmoothPageRoute<void>(
                        builder: (_) => TrailerMovieDetailsScreen(
                          provider: widget.provider,
                          movie: movie,
                          repository: widget.repository,
                          reminders: widget.reminders,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(10), child: Text(error!)),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (page < total || error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: FilledButton(
                autofocus: movies.isEmpty,
                onPressed: more,
                child: Text(error == null ? 'Load more' : 'Retry'),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                movies.isEmpty
                    ? 'No movies available.'
                    : 'All available pages loaded.',
              ),
            ),
        ],
      ),
    );
  }
}
