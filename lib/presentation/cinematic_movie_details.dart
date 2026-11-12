import 'artwork_retry.dart';
import 'details_title.dart';
import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
import '../data/tmdb_artwork_service.dart';
import '../data/omdb_ratings_service.dart';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/tmdb_cast_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'trailer_screen.dart';
import '../application/watch_history.dart';
import '../application/category_locks.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'details_screen.dart';
import 'my_list_button.dart';
import 'catalog_poster_artwork.dart';
import 'smooth_page_route.dart';
import 'title_access.dart';

String movieDisplayTitle(String title) => TmdbCastService.cleanTitle(
  title.replaceFirst(RegExp(r'[.\s]+$'), ''),
).replaceFirst(RegExp(r'[.\s]+$'), '');
String movieDisplayRating(String raw) {
  final rating = double.tryParse(raw.trim().split('/').first);
  if (rating == null || !rating.isFinite || rating < 0 || rating > 10) {
    return raw;
  }
  return '\u2605 ${rating.toStringAsFixed(1)}/10';
}

String movieDisplayDuration(String raw) {
  final parts = raw.trim().split(':');
  if ((parts.length != 2 && parts.length != 3) ||
      parts.any((p) => int.tryParse(p) == null)) {
    return raw;
  }
  final values = parts.map(int.parse).toList();
  if (values.any((v) => v < 0) ||
      values.last >= 60 ||
      (values.length == 3 && values[1] >= 60)) {
    return raw;
  }
  final totalMinutes = values.length == 3
      ? values[0] * 60 + values[1]
      : values[0];
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return [
    if (hours > 0) '${hours}h',
    if (minutes > 0 || hours == 0) '${minutes}m',
  ].join(' ');
}

class CinematicMovieDetails extends StatefulWidget {
  final IptvProvider provider;
  final MediaDetails info;
  final WatchEntry? previous;
  final bool resolving;
  final ValueChanged<bool> onPlay;
  final TmdbCastService? castService;
  final OmdbRatingsService? ratingsService;
  final TmdbArtworkService? artworkService;
  const CinematicMovieDetails({
    super.key,
    required this.provider,
    required this.info,
    required this.previous,
    required this.resolving,
    required this.onPlay,
    this.castService,
    this.ratingsService,
    this.artworkService,
  });
  @override
  State<CinematicMovieDetails> createState() => _CinematicMovieDetailsState();
}

class _CinematicMovieDetailsState extends State<CinematicMovieDetails> {
  final playFocus = FocusNode(debugLabel: 'movie primary action');
  final pageScroll = ScrollController();
  final castFocus = FocusNode(debugLabel: 'movie cast');
  final similarFocus = FocusNode(debugLabel: 'movie similar');
  late final Future<List<ContentItem>> related = loadRelated();
  List<ContentItem> relatedItems = [];
  List<MovieCredit> loadedCast = [];
  MovieRatings loadedRatings = const MovieRatings();
  Uri? titleLogo, recoveredBackdrop;
  Future<Uri?>? backdropRecovery;
  Future<Uri?> recoverBackdrop() => backdropRecovery ??= retryArtwork<Uri?>(
    scope: artworkRetries,
    load: () => (widget.artworkService ?? TmdbArtworkService.configured)
        .detailsBackdrop(info),
    usable: (value) => value != null,
    active: () => mounted,
  );
  final artworkRetries = ArtworkRetryScope();
  @override
  void initState() {
    super.initState();
    unawaited(loadCast());
    unawaited(loadRatings());
    unawaited(loadLogo());
    if (info.backdrop == null) {
      unawaited(
        recoverBackdrop().then((value) {
          if (mounted && value != null) {
            setState(() => recoveredBackdrop = value);
          }
        }),
      );
    }
  }

  Future<void> loadLogo() async {
    final logo = await retryArtwork<Uri?>(
      scope: artworkRetries,
      load: () => (widget.artworkService ?? TmdbArtworkService.configured)
          .titleLogo(info),
      usable: (value) => value != null,
      active: () => mounted,
    );
    if (mounted && logo != null) setState(() => titleLogo = logo);
  }

  Widget movieTitle(double scale) {
    final fallback = DetailsTitle(
      movieDisplayTitle(info.item.name),
      fontSize: 46 * scale,
    );
    if (titleLogo == null) return fallback;
    return Semantics(
      label: movieDisplayTitle(info.item.name),
      image: true,
      child: SharedArtworkImage(
        imageUrl: titleLogo.toString(),
        kind: ArtworkKind.logo,
        width: 360 * scale,
        height: 88 * scale,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }

  Widget ratingBadge(String text, Color color, double scale) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xb31a202b),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16 * scale,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
  Widget brandedRating(
    String source,
    String asset,
    String value,
    double scale,
  ) => Semantics(
    label: '$source $value',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            asset,
            height: 24 * scale,
            width: (source == 'IMDb' ? 48 : 24) * scale,
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18 * scale,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> loadRatings() async {
    final ratings =
        await (widget.ratingsService ?? OmdbRatingsService.configured).ratings(
          info,
        );
    if (mounted && !ratings.isEmpty) setState(() => loadedRatings = ratings);
  }

  Future<void> loadCast() async {
    final people = await retryArtwork<List<MovieCredit>>(
      scope: artworkRetries,
      load: () =>
          (widget.castService ?? TmdbCastService.configured).credits(info),
      usable: (value) => value.isNotEmpty,
      active: () => mounted,
    );
    if (mounted && people != null && people.isNotEmpty) {
      setState(() => loadedCast = people);
    }
  }

  MediaDetails get info => widget.info;
  bool get hasCast =>
      loadedCast.isNotEmpty ||
      info.cast.trim().isNotEmpty ||
      info.director.trim().isNotEmpty;
  Future<List<ContentItem>> loadRelated() async {
    final category = info.item.categoryId;
    if (category == null) return [];
    try {
      final rows = await widget.provider.getItems(
        Category(category, '', ContentType.movies),
      );
      final locks = CategoryLocks.forProvider(widget.provider);
      await locks.load();
      return rows
          .where(
            (item) =>
                item.id != info.item.id &&
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
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    artworkRetries.dispose();
    pageScroll.dispose();
    for (final node in [playFocus, castFocus, similarFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  void focusSection(FocusNode node) {
    node.requestFocus();
    if (node == playFocus) {
      if (pageScroll.hasClients) {
        unawaited(
          pageScroll.animateTo(
            0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return;
    }
    final target = node.context;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: .3,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  KeyEventResult vertical(KeyEvent event, VoidCallback up, VoidCallback down) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      up();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      down();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void belowActions() => focusSection(
    hasCast
        ? castFocus
        : relatedItems.isNotEmpty
        ? similarFocus
        : playFocus,
  );
  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(
      title,
      style: TextStyle(
        fontSize:
            29 * (MediaQuery.sizeOf(context).width / 1920).clamp(.62, 1.0),
        fontWeight: FontWeight.w500,
      ),
    ),
  );
  Future<void> trailer() =>
      openInAppTrailer(context, info.trailer!, title: info.item.name);

  Widget secondary(String label, IconData icon, VoidCallback? action) =>
      TextButton.icon(
        onPressed: action,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white30,
          backgroundColor: const Color(0xb32a2e36),
          minimumSize: const Size(0, 42),
          textStyle: TextStyle(
            fontSize:
                19 * (MediaQuery.sizeOf(context).width / 1920).clamp(.62, 1.0),
            fontWeight: FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      );
  void showMoreInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Movie Details',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                info.synopsis.isEmpty
                    ? 'No synopsis available.'
                    : info.synopsis,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              for (final row in [
                ('Release date', info.releaseDate),
                ('Duration', movieDisplayDuration(info.duration)),
                ('Genre', info.genre),
                if (loadedRatings.isEmpty)
                  ('Rating', movieDisplayRating(info.rating)),
                if (loadedRatings.imdb != null) ('IMDb', loadedRatings.imdb!),
                if (loadedRatings.rottenTomatoes != null)
                  ('Rotten Tomatoes', loadedRatings.rottenTomatoes!),
                ('Age rating', info.ageRating),
                ('Language', info.language),
                ('Director', info.director),
                ('Cast', info.cast),
                ('Format', info.item.extension ?? ''),
              ])
                if (row.$2.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      '${row.$1}: ${row.$2}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height;
    final scale = (width / 1920).clamp(.62, 1.0);
    final saved = widget.previous;
    final resume =
        saved != null &&
        saved.position > Duration.zero &&
        saved.duration > saved.position;
    final remaining = resume
        ? ((saved.duration - saved.position).inSeconds / 60).ceil()
        : 0;
    final image =
        recoveredBackdrop ?? info.backdrop ?? info.artwork ?? info.item.artwork;
    final people = loadedCast.isNotEmpty
        ? loadedCast
        : [
            for (final name in info.cast.split(RegExp(r',|;')))
              if (name.trim().isNotEmpty) MovieCredit(name.trim(), 'Cast'),
            if (info.director.trim().isNotEmpty)
              MovieCredit(info.director, 'Director'),
          ];
    return Theme(
      data: Theme.of(context).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 240),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const Color(0x66529cff)
                  : Colors.white10,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            animationDuration: const Duration(milliseconds: 240),
            overlayColor: const WidgetStatePropertyAll(Color(0x33529cff)),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? const Color(0xff64b5f6)
                    : Colors.white54,
                width: 2,
              ),
            ),
          ),
        ),
        textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
      ),
      child: ColoredBox(
        color: const Color(0xff090b10),
        child: Stack(
          children: [
            if (image != null)
              Positioned(
                top: 0,
                right: 0,
                width: width * .76,
                height: height * .86,
                child: SharedArtworkImage(
                  kind: ArtworkKind.backdrop,
                  imageUrl: image.toString(),
                  fit: BoxFit.cover,
                  alignment: Alignment.topRight,
                  errorWidget: (_, _, _) => FutureBuilder<Uri?>(
                    future: recoverBackdrop(),
                    builder: (context, snapshot) => snapshot.data == null
                        ? const SizedBox.shrink()
                        : SharedArtworkImage(
                            kind: ArtworkKind.backdrop,
                            imageUrl: snapshot.data.toString(),
                            fit: BoxFit.cover,
                            alignment: Alignment.topRight,
                          ),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xff090b10),
                      const Color(0xf0090b10),
                      const Color(0x33090b10),
                    ],
                    stops: const [0, .36, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xff090b10)],
                    stops: const [.3, .94],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              key: const PageStorageKey('cinematic-movie-scroll'),
              controller: pageScroll,
              padding: EdgeInsets.fromLTRB(width * .045, 56, width * .045, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width * .91,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: width < 700 ? width * .87 : width * .49,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                movieTitle(scale),
                                const SizedBox(height: 10),
                                Text(
                                  [
                                    TmdbCastService.configured.year(info) ?? '',
                                    movieDisplayDuration(info.duration),
                                    info.genre,
                                    info.ageRating,
                                  ].where((s) => s.isNotEmpty).join(' \u00b7 '),
                                  style: TextStyle(
                                    fontSize: 16.5 * scale,
                                    color: const Color(0xffb7bcc6),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                if (!loadedRatings.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 9),
                                    child: Wrap(
                                      spacing: 18,
                                      runSpacing: 6,
                                      children: [
                                        if (loadedRatings.imdb != null)
                                          brandedRating(
                                            'IMDb',
                                            'assets/branding/imdb.svg',
                                            loadedRatings.imdb!,
                                            scale,
                                          ),
                                        if (loadedRatings.rottenTomatoes !=
                                            null)
                                          brandedRating(
                                            'Rotten Tomatoes',
                                            'assets/branding/rotten_tomatoes.svg',
                                            loadedRatings.rottenTomatoes!,
                                            scale,
                                          ),
                                      ],
                                    ),
                                  ),
                                if (loadedRatings.isEmpty &&
                                    info.rating.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 9),
                                    child: ratingBadge(
                                      movieDisplayRating(info.rating),
                                      const Color(0xfff4cb65),
                                      scale,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  info.synopsis.isEmpty
                                      ? 'No synopsis available.'
                                      : info.synopsis,
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
                            onKeyEvent: (_, event) => vertical(
                              event,
                              () => focusSection(playFocus),
                              belowActions,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      FilledButton.icon(
                                        focusNode: playFocus,
                                        autofocus: true,
                                        onPressed: widget.resolving
                                            ? null
                                            : () => widget.onPlay(false),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: Text(
                                          widget.resolving
                                              ? 'Preparing...'
                                              : resume
                                              ? 'Resume - $remaining min left'
                                              : 'Play Movie',
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(
                                            0xff090b10,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          fixedSize: Size(
                                            (220 * scale).clamp(180, 220),
                                            42,
                                          ),
                                          textStyle: TextStyle(
                                            fontSize: 19 * scale,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                          side: const BorderSide(
                                            color: Colors.white70,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      secondary(
                                        'Trailer',
                                        Icons.play_arrow_outlined,
                                        info.trailer == null ? null : trailer,
                                      ),
                                      const SizedBox(width: 8),
                                      MyListButton(
                                        provider: widget.provider,
                                        item: info.item,
                                        showLabel: true,
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor: const Color(
                                            0xb32a2e36,
                                          ),
                                          minimumSize: const Size(0, 42),
                                          textStyle: TextStyle(
                                            fontSize:
                                                19 *
                                                (MediaQuery.sizeOf(
                                                          context,
                                                        ).width /
                                                        1920)
                                                    .clamp(.62, 1.0),
                                            fontWeight: FontWeight.w500,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      secondary(
                                        'More Info',
                                        Icons.info_outline,
                                        showMoreInfo,
                                      ),
                                      if (resume) const SizedBox(width: 8),
                                      if (resume)
                                        secondary(
                                          'Play from beginning',
                                          Icons.replay,
                                          widget.resolving
                                              ? null
                                              : () => widget.onPlay(true),
                                        ),
                                    ],
                                  ),
                                ),
                                if (resume)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 9,
                                      bottom: 4,
                                    ),
                                    child: SizedBox(
                                      width: 280 * scale,
                                      child: LinearProgressIndicator(
                                        value:
                                            (saved.position.inMilliseconds /
                                                    saved
                                                        .duration
                                                        .inMilliseconds)
                                                .clamp(0, 1),
                                        minHeight: 3,
                                        color: const Color(0xff64b5f6),
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (people.isNotEmpty) ...[
                    section('Cast & Crew'),
                    SizedBox(
                      height: 150,
                      child: Focus(
                        onKeyEvent: (_, event) => vertical(
                          event,
                          () => focusSection(playFocus),
                          () => focusSection(
                            relatedItems.isNotEmpty ? similarFocus : playFocus,
                          ),
                        ),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: people.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) => CastCreditCard(
                            key: ValueKey('cast-credit:${people[index].name}'),
                            credit: people[index],
                            focusNode: index == 0 ? castFocus : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                  FutureBuilder<List<ContentItem>>(
                    future: related,
                    builder: (context, snapshot) {
                      relatedItems = snapshot.data ?? [];
                      if (relatedItems.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          section('You May Also Like'),
                          SizedBox(
                            height: 214,
                            child: Focus(
                              onKeyEvent: (_, event) => vertical(
                                event,
                                () => focusSection(
                                  hasCast ? castFocus : playFocus,
                                ),
                                () {},
                              ),
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: relatedItems.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 20),
                                itemBuilder: (context, index) {
                                  final item = relatedItems[index];
                                  return SizedBox(
                                    width: 140,
                                    child: TextButton(
                                      focusNode: index == 0
                                          ? similarFocus
                                          : null,
                                      style:
                                          TextButton.styleFrom(
                                            padding: const EdgeInsets.all(3),
                                            foregroundColor: Colors.white,
                                            animationDuration: const Duration(
                                              milliseconds: 170,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ).copyWith(
                                            side:
                                                WidgetStateProperty.resolveWith(
                                                  (states) => BorderSide(
                                                    color:
                                                        states.contains(
                                                          WidgetState.focused,
                                                        )
                                                        ? const Color(
                                                            0xff64b5f6,
                                                          )
                                                        : Colors.transparent,
                                                    width: 2,
                                                  ),
                                                ),
                                          ),
                                      onPressed: () async {
                                        if (!await requestTitleAccess(
                                              context,
                                              widget.provider,
                                              item,
                                            ) ||
                                            !context.mounted) {
                                          return;
                                        }
                                        await Navigator.of(context).push(
                                          SmoothPageRoute<void>(
                                            builder: (_) => DetailsScreen(
                                              provider: widget.provider,
                                              item: item,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: CatalogPosterArtwork(
                                              item: item,
                                              service: widget.artworkService,
                                              provider: widget.provider,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 36,
                                            child: Text(
                                              movieDisplayTitle(item.name),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                height: 1.2,
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
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 12,
              child: BackButton(
                color: Colors.white,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Focusable for horizontal remote browsing, with no activation action.
class CastCreditCard extends StatelessWidget {
  final MovieCredit credit;
  final FocusNode? focusNode;
  const CastCreditCard({super.key, required this.credit, this.focusNode});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 132,
    child: Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) =>
          (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: Builder(
        builder: (context) => AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Focus.of(context).hasFocus
                ? const Color(0xff354962)
                : const Color(0xaa262d37),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: Focus.of(context).hasFocus
                  ? const Color(0xff64b5f6)
                  : Colors.transparent,
            ),
          ),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white, fontSize: 13),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Container(
                    width: 64,
                    height: 64,
                    color: const Color(0xff202733),
                    child: credit.photo == null
                        ? const ColoredBox(
                            color: Color(0xff202733),
                            child: Icon(
                              Icons.person_outline,
                              color: Colors.white54,
                              size: 32,
                            ),
                          )
                        : SharedArtworkImage(
                            imageUrl: credit.photo.toString(),
                            kind: ArtworkKind.cast,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.6),
                            placeholder: (_, _) =>
                                const ColoredBox(color: Color(0xff202733)),
                            errorWidget: (_, _, _) => const Icon(
                              Icons.person_outline,
                              color: Colors.white54,
                              size: 32,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  credit.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  credit.role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
