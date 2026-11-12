import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

/// Fixed-size, lazy horizontal row with explicit logical remote traversal.
class MediaHorizontalRail extends StatefulWidget {
  final int count, initialIndex;
  final double width, height;
  final Object? contentKey;
  final GlobalKey? verticalRevealKey;
  final VoidCallback up, down;
  final VoidCallback? onLeftBoundary, onRightBoundary;
  final Widget Function(int, FocusNode) itemBuilder;
  const MediaHorizontalRail({
    super.key,
    required this.count,
    required this.width,
    required this.height,
    required this.up,
    required this.down,
    required this.itemBuilder,
    this.initialIndex = 0,
    this.contentKey,
    this.verticalRevealKey,
    this.onLeftBoundary,
    this.onRightBoundary,
  });
  @override
  State<MediaHorizontalRail> createState() => MediaHorizontalRailState();
}

class MediaHorizontalRailState extends State<MediaHorizontalRail> {
  // Each mounted rail owns its position. Nested rows otherwise share the
  // catalog's PageStorage identifier and can inherit another row's offset.
  final controller = ScrollController(keepScrollOffset: false);
  final nodes = <int, FocusNode>{};
  int current = 0;
  int navigation = 0;
  bool navigated = false;
  double? scrollingTo;
  int scrollGeneration = 0;
  @override
  void initState() {
    super.initState();
    current = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant MediaHorizontalRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) {
      navigated = false;
      scrollingTo = null;
      current = widget.initialIndex;
      if (controller.hasClients) controller.jumpTo(0);
    } else if (!navigated && oldWidget.initialIndex != widget.initialIndex) {
      current = widget.initialIndex;
    }
  }

  FocusNode node(int index) => nodes.putIfAbsent(index, () {
    final result = FocusNode(debugLabel: 'series row item $index');
    result.addListener(() {
      if (result.hasFocus) {
        navigated = true;
        current = index;
        unawaited(alignHorizontal(index));
        final target =
            widget.verticalRevealKey?.currentContext?.findRenderObject() ??
            context.findRenderObject();
        if (target != null) {
          // Only scroll the page vertically here. The generic ensureVisible
          // also shifts the horizontal row to a fractional tile offset.
          final vertical = Scrollable.maybeOf(context, axis: Axis.vertical);
          if (vertical != null) {
            unawaited(
              vertical.position.ensureVisible(
                target,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: .25,
              ),
            );
          }
        }
      }
    });
    return result;
  });
  Future<void> alignHorizontal(int index) async {
    if (!controller.hasClients || widget.count == 0) return;
    final slots = (controller.position.viewportDimension / widget.width)
        .floor()
        .clamp(1, widget.count);
    var first = ((scrollingTo ?? controller.offset) / widget.width).round();
    if (index < first) first = index;
    if (index >= first + slots) first = index - slots + 1;
    final offset = (first * widget.width).clamp(
      0.0,
      controller.position.maxScrollExtent,
    );
    if (scrollingTo != null && (scrollingTo! - offset).abs() < .5) return;
    if ((controller.offset - offset).abs() > .5) {
      scrollingTo = offset;
      final scrollTicket = ++scrollGeneration;
      try {
        await controller.animateTo(
          offset,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } finally {
        if (scrollTicket == scrollGeneration) scrollingTo = null;
      }
    }
  }

  void focusCurrent() => unawaited(focusAt(current));
  Future<void> focusAt(int index) async {
    if (widget.count == 0) return;
    final ticket = ++navigation;
    navigated = true;
    current = index.clamp(0, widget.count - 1);
    final target = current;
    // Focus mounted neighbours immediately: the outgoing and incoming cards
    // animate together while the row moves, instead of waiting for scrolling.
    if (nodes[target]?.context != null &&
        nodes.values.any((node) => node.hasFocus)) {
      node(target).requestFocus();
      return;
    }
    await alignHorizontal(target);
    if (!mounted || ticket != navigation) return;
    // Lazy ListView children are attached after scrolling lays out the target.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ticket == navigation) node(target).requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    for (final n in nodes.values) {
      n.dispose();
    }
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.up();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.down();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (current == 0 && widget.onLeftBoundary != null) {
          widget.onLeftBoundary!();
        } else {
          unawaited(focusAt(current - 1));
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (current == widget.count - 1 && widget.onRightBoundary != null) {
          widget.onRightBoundary!();
        } else {
          unawaited(focusAt(current + 1));
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slots = (constraints.maxWidth / widget.width).floor();
          final trailing = slots > 0
              ? constraints.maxWidth - slots * widget.width
              : 0.0;
          return ListView.builder(
            padding: EdgeInsets.only(right: trailing),
            key: ValueKey(widget.contentKey),
            controller: controller,
            scrollDirection: Axis.horizontal,
            itemExtent: widget.width,
            scrollCacheExtent: ScrollCacheExtent.pixels(widget.width),
            itemCount: widget.count,
            itemBuilder: (context, index) =>
                widget.itemBuilder(index, node(index)),
          );
        },
      ),
    ),
  );
}
