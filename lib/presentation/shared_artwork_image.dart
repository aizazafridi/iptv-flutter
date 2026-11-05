import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../application/browsing_mode.dart';
import '../data/artwork_repository.dart';

/// Visibility-gated adapter over the existing disk and decoded-image caches.
class SharedArtworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit? fit;
  final Alignment alignment;
  final double? width, height;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Widget Function(BuildContext, ImageProvider)? imageBuilder;
  final ArtworkKind kind;
  final ArtworkPriority? priority;
  const SharedArtworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
    this.kind = ArtworkKind.poster,
    this.priority,
  });
  @override
  State<SharedArtworkImage> createState() => _SharedArtworkImageState();
}

class _SharedArtworkImageState extends State<SharedArtworkImage> {
  final owner = Object();
  final watch = Stopwatch()..start();
  ScrollPosition? horizontal, vertical;
  bool visible = false,
      near = false,
      decoded = false,
      scheduled = false,
      visibleRecorded = false;
  String? requested;
  int? decodeWidth;
  Timer? retryTimer;
  int retryAttempt = 0, imageRevision = 0;
  void retryDownload(int target) {
    if (retryTimer != null || retryAttempt >= 3) return;
    final failedUrl = url;
    retryTimer = Timer(Duration(seconds: [2, 6, 15][retryAttempt]), () async {
      retryTimer = null;
      if (!mounted ||
          failedUrl != url ||
          !near ||
          BrowsingModeSettings.instance.lite) {
        return;
      }
      retryAttempt++;
      await ResizeImage.resizeIfNeeded(
        target,
        null,
        CachedNetworkImageProvider(
          failedUrl,
          cacheManager: ArtworkRepository.instance,
          cacheKey: ArtworkRepository.cacheKey(failedUrl),
        ),
      ).evict();
      if (!mounted || failedUrl != url) return;
      setState(() => imageRevision++);
    });
  }

  ArtworkKind get kind => widget.kind;
  String get url => ArtworkRepository.variant(widget.imageUrl, kind);
  @override
  void initState() {
    super.initState();
    BrowsingModeSettings.instance.addListener(check);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    horizontal?.removeListener(check);
    vertical?.removeListener(check);
    horizontal = Scrollable.maybeOf(context, axis: Axis.horizontal)?.position;
    vertical = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    horizontal?.addListener(check);
    vertical?.addListener(check);
    check();
  }

  @override
  void didUpdateWidget(covariant SharedArtworkImage old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl || old.kind != widget.kind) {
      retryTimer?.cancel();
      retryTimer = null;
      retryAttempt = 0;
      imageRevision++;
      release();
      decoded = false;
      visibleRecorded = false;
      visible = false;
      near = false;
      decodeWidth = null;
      watch.reset();
      watch.start();
      check();
    }
    check();
  }

  void release() {
    if (requested != null) ArtworkRepository.release(requested!, owner);
    requested = null;
  }

  void check() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      var screen = Offset.zero & MediaQuery.sizeOf(context);
      var offstage = false;
      context.visitAncestorElements((element) {
        final ancestor = element.renderObject;
        if (ancestor is RenderOffstage && ancestor.offstage) offstage = true;
        if (ancestor is RenderAbstractViewport &&
            ancestor is RenderBox &&
            (ancestor as RenderBox).hasSize) {
          final viewport = ancestor as RenderBox;
          screen = screen.intersect(
            viewport.localToGlobal(Offset.zero) & viewport.size,
          );
        }
        return true;
      });
      final lite = BrowsingModeSettings.instance.lite;
      final onScreen =
          !lite && !offstage && !screen.isEmpty && rect.overlaps(screen);
      final adjacent =
          !lite &&
          !offstage &&
          !screen.isEmpty &&
          rect.overlaps(screen.inflate(160));
      final eligible = kind == ArtworkKind.cast ? onScreen : adjacent;
      if (!eligible) {
        release();
      } else {
        if (requested != url) {
          release();
          requested = url;
          watch.reset();
          watch.start();
          decoded = false;
          visibleRecorded = false;
          ArtworkMetrics.record(
            'metadata_available',
            url: url,
            values: {'kind': kind.name},
          );
        }
        ArtworkRepository.demand(
          url,
          owner,
          !onScreen
              ? ArtworkPriority.nearVisible
              : widget.priority ??
                    (kind == ArtworkKind.cast
                        ? ArtworkPriority.cast
                        : kind == ArtworkKind.backdrop
                        ? ArtworkPriority.backdrop
                        : ArtworkPriority.visible),
        );
      }
      if (visible != onScreen || near != eligible) {
        setState(() {
          visible = onScreen;
          near = eligible;
        });
      }
      if (onScreen && decoded) recordDisplay();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    horizontal?.removeListener(check);
    vertical?.removeListener(check);
    BrowsingModeSettings.instance.removeListener(check);
    release();
    super.dispose();
  }

  void recordDisplay() {
    if (!visible || visibleRecorded) return;
    visibleRecorded = true;
    ArtworkMetrics.record(
      'first_display_frame',
      url: url,
      values: {
        'elapsed_ms': watch.elapsedMilliseconds,
        'visible': true,
        'kind': kind.name,
      },
    );
  }

  Widget empty() =>
      widget.placeholder?.call(context, url) ??
      const ColoredBox(color: Color(0xff1b2431));
  @override
  Widget build(BuildContext context) {
    if (!near || BrowsingModeSettings.instance.lite) {
      check();
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: empty(),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final budget = switch (kind) {
          ArtworkKind.poster => 200,
          ArtworkKind.cast => 96,
          ArtworkKind.episode => 320,
          ArtworkKind.backdrop => 960,
          ArtworkKind.logo => 500,
        };
        final logical = widget.width?.isFinite == true
            ? widget.width!
            : constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : budget / dpr;
        final pixels = (logical * dpr).ceil().clamp(1, budget);
        // Small buckets reuse decoded images across similarly sized cards.
        final target = ((pixels / 32).ceil() * 32).clamp(32, budget);
        if (decodeWidth != target) {
          decodeWidth = target;
          final provider = ResizeImage.resizeIfNeeded(
            target,
            null,
            CachedNetworkImageProvider(
              url,
              cacheManager: ArtworkRepository.instance,
              cacheKey: ArtworkRepository.cacheKey(url),
            ),
          );
          unawaited(
            provider.obtainKey(createLocalImageConfiguration(context)).then((
              key,
            ) {
              if (mounted) {
                final status = PaintingBinding.instance.imageCache.statusForKey(
                  key,
                );
                ArtworkMetrics.record(
                  'memory_lookup',
                  url: url,
                  values: {
                    'keep_alive': status.keepAlive,
                    'live': status.live,
                    'pending': status.pending,
                    'decode_width': target,
                  },
                );
              }
            }),
          );
        }
        return CachedNetworkImage(
          key: ValueKey('$url:$imageRevision'),
          imageUrl: url,
          cacheKey: ArtworkRepository.cacheKey(url),
          cacheManager: ArtworkRepository.instance,
          memCacheWidth: target,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          alignment: widget.alignment,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => empty(),
          errorWidget: (context, url, error) {
            retryDownload(target);
            return widget.errorWidget?.call(context, url, error) ?? empty();
          },
          imageBuilder: (context, provider) {
            if (!decoded) {
              decoded = true;
              ArtworkMetrics.record(
                'decoded_frame_ready',
                url: url,
                values: {
                  'elapsed_ms': watch.elapsedMilliseconds,
                  'decode_width': target,
                  'kind': kind.name,
                  if (ArtworkMetrics.fileReadyUs[ArtworkMetrics.id(url)]
                      case final ready?)
                    'file_to_decoded_ms':
                        (DateTime.now().microsecondsSinceEpoch - ready) / 1000,
                },
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  recordDisplay();
                  ArtworkMetrics.sampleMemory();
                }
              });
            }
            return widget.imageBuilder?.call(context, provider) ??
                Image(
                  image: provider,
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  alignment: widget.alignment,
                  gaplessPlayback: true,
                );
          },
        );
      },
    );
  }
}
