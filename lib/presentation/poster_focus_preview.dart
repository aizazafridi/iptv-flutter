import '../data/artwork_repository.dart';
import 'shared_artwork_image.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../application/browsing_mode.dart';
import '../domain/models.dart';

/// One overlay, one delay, and one animation for an entire browsing surface.
class PosterPreviewController extends ChangeNotifier {
  OverlayEntry? _entry;
  _PosterPreviewAnchorState? _anchor;
  Timer? _delay;
  bool information = false;
  Future<void> _detailLane = Future.value();
  bool _disposed = false;
  bool get active => _entry != null;
  bool owns(Object anchor) => identical(_anchor, anchor) && active;

  void _show(_PosterPreviewAnchorState anchor) {
    if (_disposed || BrowsingModeSettings.instance.lite) return;
    close();
    _anchor = anchor;
    if (anchor.geometry() == null) {
      _anchor = null;
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => _PosterPreview(controller: this, anchor: anchor),
    );
    Overlay.of(anchor.context).insert(_entry!);
    notifyListeners();
    _delay = Timer(const Duration(milliseconds: 450), () {
      if (_disposed ||
          !identical(_anchor, anchor) ||
          !anchor.mounted ||
          !anchor.node.hasFocus) {
        return;
      }
      information = true;
      _entry?.markNeedsBuild();
      _detailLane = _detailLane.then((_) async {
        if (_disposed || !owns(anchor) || !anchor.mounted) return;
        await anchor.loadInformation();
        if (!_disposed && owns(anchor) && anchor.mounted) {
          _entry?.markNeedsBuild();
        }
      });
    });
  }

  bool _positionScheduled = false;
  void updatePosition() {
    if (_positionScheduled || _disposed || !active) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (_disposed) return;
      final anchor = _anchor;
      if (anchor == null) return;
      if (!anchor.mounted ||
          anchor.geometry() == null ||
          ModalRoute.of(anchor.context)?.isCurrent != true) {
        close();
      } else {
        _entry?.markNeedsBuild();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _focusChanged(_PosterPreviewAnchorState anchor) {
    scheduleMicrotask(() {
      if (_disposed || !identical(_anchor, anchor) || !anchor.mounted) return;
      if (!anchor.node.hasFocus && !anchor.actions.hasFocus) close();
    });
  }

  bool dismiss({bool restoreFocus = true}) {
    if (!active) return false;
    final anchor = _anchor;
    if (restoreFocus && anchor != null) anchor.suppressUntilBlur = true;
    close();
    if (restoreFocus && anchor?.mounted == true) anchor!.node.requestFocus();
    return true;
  }

  void close({bool notify = true}) {
    _delay?.cancel();
    _delay = null;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _anchor = null;
    information = false;
    if (!_disposed && notify) notifyListeners();
  }

  @override
  void dispose() {
    close(notify: false);
    _disposed = true;
    super.dispose();
  }
}

/// Owns a node only when the catalog has not supplied an existing one.
class PosterPreviewAnchor extends StatefulWidget {
  final PosterPreviewController controller;
  final ContentItem item;
  final FocusNode? focusNode;
  final Widget Function(FocusNode) cardBuilder;
  final Widget poster;
  final VoidCallback onPlay, onDetails;
  final Widget myListAction;
  final bool resume;
  final bool wide, showActions;
  final Future<MediaDetails> Function()? informationLoader;
  const PosterPreviewAnchor({
    super.key,
    required this.controller,
    required this.item,
    this.focusNode,
    required this.cardBuilder,
    required this.poster,
    required this.onPlay,
    required this.onDetails,
    required this.myListAction,
    this.resume = false,
    this.wide = false,
    this.showActions = true,
    this.informationLoader,
  });
  @override
  State<PosterPreviewAnchor> createState() => _PosterPreviewAnchorState();
}

class _PosterPreviewAnchorState extends State<PosterPreviewAnchor> {
  final link = LayerLink();
  final anchorKey = GlobalKey();
  final actions = FocusScopeNode(debugLabel: 'poster preview actions');
  final play = FocusNode(debugLabel: 'poster preview play');
  late final node =
      widget.focusNode ?? FocusNode(debugLabel: 'movie grid ${widget.item.id}');
  ScrollPosition? scroll, verticalScroll;
  bool suppressUntilBlur = false;
  MediaDetails? information;
  bool informationAttempted = false;
  Future<void> loadInformation() async {
    if (informationAttempted || widget.informationLoader == null) return;
    informationAttempted = true;
    try {
      information = await widget.informationLoader!();
    } catch (_) {
      informationAttempted = false;
    }
  }

  @override
  void initState() {
    super.initState();
    node.addListener(changed);
    actions.addListener(actionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    scroll?.removeListener(widget.controller.updatePosition);
    if (verticalScroll != scroll) {
      verticalScroll?.removeListener(widget.controller.updatePosition);
    }
    scroll = Scrollable.maybeOf(context)?.position;
    scroll?.addListener(widget.controller.updatePosition);
    verticalScroll = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (verticalScroll != scroll) {
      verticalScroll?.addListener(widget.controller.updatePosition);
    }
    if (widget.controller.owns(this)) widget.controller.updatePosition();
    if (BrowsingModeSettings.instance.lite && widget.controller.owns(this)) {
      widget.controller.close();
    }
  }

  void actionChanged() => widget.controller._focusChanged(this);
  void changed() {
    if (node.hasFocus) {
      if (suppressUntilBlur || widget.controller.owns(this)) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            node.hasFocus &&
            ModalRoute.of(context)?.isCurrent == true) {
          widget.controller._show(this);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      suppressUntilBlur = false;
      widget.controller._focusChanged(this);
    }
  }

  ({Rect anchor, Rect bounds, RenderBox overlay})? geometry() {
    if (!mounted) return null;
    final box = anchorKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context).context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        overlay is! RenderBox ||
        !overlay.hasSize) {
      return null;
    }
    final mq = MediaQuery.of(context);
    var bounds = Rect.fromLTRB(
      mq.padding.left + 8,
      mq.padding.top + 8,
      mq.size.width - mq.padding.right - 8,
      mq.size.height - mq.padding.bottom - 8,
    );
    final rect = box.localToGlobal(Offset.zero) & box.size;
    Rect? viewport;
    Rect? outerViewport;
    RenderObject? parent = box.parent;
    while (parent != null) {
      if (parent is RenderAbstractViewport &&
          parent is RenderBox &&
          (parent as RenderBox).hasSize) {
        final viewportBox = parent as RenderBox;
        final viewRect =
            viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
        viewport = viewport == null ? viewRect : viewport.intersect(viewRect);
        outerViewport = viewRect;
        if (!widget.wide) break;
      }
      parent = parent.parent;
    }
    if (viewport != null) {
      if (!rect.overlaps(viewport) ||
          rect.intersect(viewport).height < math.min(24, rect.height)) {
        return null;
      }
      // Keep floating previews within the catalog, away from its sidebar/header.
      bounds = bounds.intersect(widget.wide ? outerViewport! : viewport);
    }
    if (bounds.width < 80 || bounds.height < 80) return null;
    return (anchor: rect, bounds: bounds, overlay: overlay);
  }

  @override
  void dispose() {
    if (widget.controller.owns(this)) widget.controller.close(notify: false);
    scroll?.removeListener(widget.controller.updatePosition);
    if (verticalScroll != scroll) {
      verticalScroll?.removeListener(widget.controller.updatePosition);
    }
    node.removeListener(changed);
    actions.removeListener(actionChanged);
    if (widget.focusNode == null) node.dispose();
    actions.dispose();
    play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    key: anchorKey,
    link: link,
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (widget.showActions &&
            (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack) &&
            widget.controller.dismiss()) {
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.controller.owns(this) &&
            widget.controller.information &&
            widget.showActions) {
          play.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (_, child) => Opacity(
          alwaysIncludeSemantics: true,
          opacity: widget.controller.owns(this) ? 0 : 1,
          child: child,
        ),
        child: widget.cardBuilder(node),
      ),
    ),
  );
}

class _PosterPreview extends StatefulWidget {
  final PosterPreviewController controller;
  final _PosterPreviewAnchorState anchor;
  const _PosterPreview({required this.controller, required this.anchor});
  @override
  State<_PosterPreview> createState() => _PosterPreviewState();
}

class _PosterPreviewState extends State<_PosterPreview>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  @override
  void initState() {
    super.initState();
    animation.forward();
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anchor;
    final g = a.geometry();
    if (g == null) return const SizedBox.shrink();
    final info = widget.controller.information;
    final scale = MediaQuery.disableAnimationsOf(context)
        ? 1.0
        : a.widget.item.type == ContentType.movies
        ? 1.20
        : 1.12;
    final width = math.min(
      g.anchor.width * (a.widget.wide ? 1.8 : 1),
      g.bounds.width / scale,
    );
    final infoHeight = info ? (a.widget.wide ? 142.0 : 96.0) : 0.0;
    final height = math.min(
      g.anchor.height,
      math.max(60.0, g.bounds.height / scale - infoHeight),
    );
    final total = (height + infoHeight) * scale;
    final above =
        a.widget.item.type != ContentType.movies &&
        info &&
        g.anchor.top + total > g.bounds.bottom &&
        g.anchor.top - infoHeight * scale >= g.bounds.top;
    final left = g.anchor.center.dx - width * scale / 2;
    final top =
        g.anchor.top - (above ? infoHeight * scale : height * (scale - 1) / 2);
    final desired = Offset(
      left.clamp(
        g.bounds.left,
        math.max(g.bounds.left, g.bounds.right - width * scale),
      ),
      top.clamp(g.bounds.top, math.max(g.bounds.top, g.bounds.bottom - total)),
    );
    final offset = desired - g.anchor.topLeft;
    final item = a.widget.item;
    final details = a.information;
    final panel = SizedBox(
      height: infoHeight,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.type == ContentType.movies ||
                item.releaseYear != null ||
                item.rating != null)
              Text(
                [
                  if (item.releaseYear != null) '${item.releaseYear}',
                  if (item.type == ContentType.movies) 'Movie',
                  if (item.rating != null)
                    '\u2605 ${item.rating!.toStringAsFixed(1)}',
                ].join(' \u00b7 '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xffb7bcc6)),
              ),
            if (a.widget.wide && details != null) ...[
              const SizedBox(height: 6),
              if (details.genre.isNotEmpty || details.duration.isNotEmpty)
                Text(
                  [
                    if (details.genre.isNotEmpty) details.genre,
                    if (details.duration.isNotEmpty) details.duration,
                  ].join(' - '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: Color(0xffb7bcc6),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                details.synopsis,
                maxLines: a.widget.showActions ? 2 : 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
            ],
            const Spacer(),
            if (a.widget.showActions)
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        focusNode: a.play,
                        onPressed: a.widget.onPlay,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          a.widget.resume ? 'Resume' : 'Play',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: a.widget.onDetails,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    SizedBox(width: 32, child: a.widget.myListAction),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    final poster = SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: a.widget.wide && details?.backdrop != null
                  ? SharedArtworkImage(
                      imageUrl: details!.backdrop.toString(),
                      kind: ArtworkKind.backdrop,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => a.widget.poster,
                    )
                  : a.widget.poster,
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 38,
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            if (item.type != ContentType.movies && item.releaseYear != null)
              Text(
                '${item.releaseYear}',
                style: const TextStyle(fontSize: 12, color: Color(0xffb7bcc6)),
              ),
          ],
        ),
      ),
    );
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: a.link,
        showWhenUnlinked: false,
        offset: offset,
        child: AnimatedBuilder(
          animation: animation,
          child: SizedBox(
            width: width,
            child: Material(
              key: const ValueKey('floating-poster-preview'),
              color: const Color(0xff1b222d),
              elevation: 8,
              shadowColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
                side: const BorderSide(color: Color(0xff64b5f6), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: FocusScope(
                node: a.actions,
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if ([
                      LogicalKeyboardKey.escape,
                      LogicalKeyboardKey.goBack,
                      LogicalKeyboardKey.arrowUp,
                    ].contains(event.logicalKey)) {
                      widget.controller.dismiss();
                      return KeyEventResult.handled;
                    }
                    if ([
                      LogicalKeyboardKey.arrowLeft,
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowDown,
                    ].contains(event.logicalKey)) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                          !a.play.hasFocus) {
                        return KeyEventResult.ignored;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        return KeyEventResult.ignored;
                      }
                      widget.controller.dismiss();
                      a.node.focusInDirection(
                        event.logicalKey == LogicalKeyboardKey.arrowLeft
                            ? TraversalDirection.left
                            : TraversalDirection.down,
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (above && info) panel,
                      poster,
                      if (!above && info) panel,
                    ],
                  ),
                ),
              ),
            ),
          ),
          builder: (_, child) => Transform.scale(
            alignment: Alignment.topLeft,
            scale:
                1 +
                (scale - 1) * Curves.easeOutCubic.transform(animation.value),
            child: child,
          ),
        ),
      ),
    );
  }
}
