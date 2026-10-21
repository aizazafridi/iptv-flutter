import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../domain/models.dart';
import 'widgets.dart';

class CardRowNavigation {
  Future<bool> Function()? focusFirst;
}

/// Rows load only when visible; horizontal lists build posters on demand.
class CategoryCardRow extends StatefulWidget {
  final String title;
  final CardRowNavigation? navigation;
  final VoidCallback? onTitleReady;
  final VoidCallback? onEmpty;
  final FocusNode? entryFocusNode;
  final FocusNode Function(int)? itemFocusNode;
  final Widget? headerAction;
  final Widget Function(ContentItem item)? itemAction;
  final Future<List<ContentItem>> Function(bool refresh) load;
  final VoidCallback onMore;
  final void Function(ContentItem) onOpen;
  const CategoryCardRow({
    super.key,
    required this.title,
    this.navigation,
    this.onTitleReady,
    this.onEmpty,
    this.entryFocusNode,
    this.itemFocusNode,
    this.headerAction,
    this.itemAction,
    required this.load,
    required this.onMore,
    required this.onOpen,
  });
  @override
  State<CategoryCardRow> createState() => _CategoryCardRowState();
}

class _CategoryCardRowState extends State<CategoryCardRow> {
  late Future<List<ContentItem>> items;
  final scroll = ScrollController();
  final pending = Completer<List<ContentItem>>();
  ScrollPosition? verticalPosition;
  bool started = false, titleNotified = false;
  bool visibilityScheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (verticalPosition != position) {
      verticalPosition?.removeListener(scheduleVisibility);
      verticalPosition = position;
      position?.addListener(scheduleVisibility);
    }
    scheduleVisibility();
  }

  void scheduleVisibility() {
    if (started || visibilityScheduled) return;
    visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      visibilityScheduled = false;
      if (!mounted || started) return;
      final box = context.findRenderObject();
      final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (viewport is RenderBox && viewport.hasSize) {
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top >= viewport.size.height || top + box.size.height <= 0) return;
      }
      started = true;
      pending.complete(
        widget.load(false).then((rows) {
          if (mounted && rows.isEmpty) widget.onEmpty?.call();
          return rows;
        }),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    items = pending.future;
    widget.navigation?.focusFirst = focusFirst;
  }

  @override
  void dispose() {
    widget.navigation?.focusFirst = null;
    verticalPosition?.removeListener(scheduleVisibility);
    scroll.dispose();
    super.dispose();
  }

  int titleCount = 0, pageStart = 0, pageSize = 1;
  bool changingPage = false;
  Future<bool> focusFirst() async {
    if (!mounted || titleCount == 0) return false;
    if (pageStart != 0) setState(() => pageStart = 0);
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return false;
    final node = widget.itemFocusNode?.call(0);
    if (node?.context == null) return false;
    node!.requestFocus();
    return true;
  }

  Future<void> moveTitle(int direction) async {
    if (changingPage) return;
    int? current;
    for (
      var index = pageStart;
      index < (pageStart + pageSize).clamp(0, titleCount);
      index++
    ) {
      if (widget.itemFocusNode?.call(index).hasPrimaryFocus == true) {
        current = index;
        break;
      }
    }
    if (current == null) return;
    final next = current + direction;
    if (next < 0) return;
    if (next >= titleCount) {
      widget.entryFocusNode?.requestFocus();
      return;
    }
    changingPage = true;
    try {
      if (next < pageStart || next >= pageStart + pageSize) {
        setState(() => pageStart = (next ~/ pageSize) * pageSize);
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted) widget.itemFocusNode?.call(next).requestFocus();
    } finally {
      changingPage = false;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (widget.headerAction != null) widget.headerAction!,
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: AsyncView(
            future: items,
            retry: () => setState(() => items = widget.load(true)),
            builder: (rows) => rows.isEmpty
                ? const EmptyState('No items available')
                : LayoutBuilder(
                    builder: (context, constraints) {
                      titleCount = rows.length;
                      pageSize = ((constraints.maxWidth - 24) / 125)
                          .floor()
                          .clamp(1, 100);
                      return Focus(
                        canRequestFocus: false,
                        onKeyEvent: (_, event) {
                          if (event is! KeyDownEvent &&
                              event is! KeyRepeatEvent) {
                            return KeyEventResult.ignored;
                          }
                          final direction =
                              event.logicalKey == LogicalKeyboardKey.arrowRight
                              ? 1
                              : event.logicalKey == LogicalKeyboardKey.arrowLeft
                              ? -1
                              : 0;
                          if (direction == 0) return KeyEventResult.ignored;
                          moveTitle(direction);
                          return KeyEventResult.handled;
                        },
                        child: ListView.builder(
                          controller: scroll,
                          scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: (rows.length - pageStart).clamp(
                            0,
                            pageSize,
                          ),
                          itemBuilder: (_, pageIndex) {
                            final index = pageStart + pageIndex;
                            final item = rows[index];
                            if (index == 0 && !titleNotified) {
                              titleNotified = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) widget.onTitleReady?.call();
                              });
                            }
                            return SizedBox(
                              width: 125,
                              child: FocusCard(
                                revealOnFocus: false,
                                focusNode: widget.itemFocusNode?.call(index),
                                onTap: () => widget.onOpen(item),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: item.type == ContentType.live
                                            ? ChannelLogo(item.artwork)
                                            : Artwork(item.artwork),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (widget.itemAction != null)
                                          widget.itemAction!(item),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton(
            focusNode: widget.entryFocusNode,
            onPressed: widget.onMore,
            child: const Text('All'),
          ),
        ),
      ],
    ),
  );
}
