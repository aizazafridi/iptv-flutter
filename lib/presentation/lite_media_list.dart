import 'history_removal.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

class LiteMediaTile extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? progress;
  const LiteMediaTile({
    super.key,
    required this.title,
    this.subtitle = '',
    this.icon = Icons.movie_outlined,
    required this.onOpen,
    this.onRemove,
    this.focusNode,
    this.autofocus = false,
    this.progress,
  });
  @override
  Widget build(BuildContext context) => onRemove == null
      ? tile(context)
      : HistoryRemoteAction(
          onOpen: onOpen,
          onRemove: onRemove!,
          child: tile(context),
        );
  Widget tile(BuildContext context) => TextButton(
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: onOpen,
    onLongPress: onRemove,
    style: ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 60)),
      foregroundColor: const WidgetStatePropertyAll(Colors.white),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused)
            ? const Color(0xff30445d)
            : const Color(0xff1b2431),
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(
          color: s.contains(WidgetState.focused)
              ? const Color(0xff64b5f6)
              : Colors.transparent,
          width: 2,
        ),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      animationDuration: Duration.zero,
    ),
    child: Row(
      children: [
        Icon(icon, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: 'Roboto', fontSize: 16),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xffaab8c9),
                  ),
                ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0, 1),
                    minHeight: 2,
                  ),
                ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, size: 20),
      ],
    ),
  );
}

/// Fixed extent permits reliable remote traversal through unmounted lazy rows.
class LiteMediaList extends StatefulWidget {
  final List<ContentItem> items;
  final Future<void> Function(ContentItem) onOpen;
  final void Function(ContentItem)? onRemove;
  final String Function(ContentItem)? subtitle;
  final double? Function(ContentItem)? progress;
  final VoidCallback? up, left;
  final String? selectedId;
  final bool restoreFocus;
  final FocusNode? entryFocus;
  final ValueChanged<String>? onFocus;
  const LiteMediaList({
    super.key,
    required this.items,
    required this.onOpen,
    this.onRemove,
    this.subtitle,
    this.progress,
    this.up,
    this.left,
    this.selectedId,
    this.restoreFocus = false,
    this.onFocus,
    this.entryFocus,
  });
  @override
  State<LiteMediaList> createState() => _LiteMediaListState();
}

class _LiteMediaListState extends State<LiteMediaList> {
  final scroll = ScrollController(keepScrollOffset: false);
  final nodes = <String, FocusNode>{};
  int current = 0;
  int ticket = 0;
  String nodeKey(ContentItem item) => '${item.type.name}:${item.id}';
  @override
  void initState() {
    super.initState();
    current = widget.items.indexWhere((i) => i.id == widget.selectedId);
    if (current < 0) current = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients && current > 0) {
        scroll.jumpTo(
          (current * 68.0).clamp(0, scroll.position.maxScrollExtent),
        );
      }
      if (mounted &&
          widget.restoreFocus &&
          widget.selectedId != null &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(focus(current));
      }
    });
  }

  Future<void> focus(int index) async {
    if (widget.items.isEmpty) return;
    final turn = ++ticket;
    current = index.clamp(0, widget.items.length - 1);
    if (scroll.hasClients) {
      final top = current * 68.0, bottom = (current + 1) * 68.0;
      if (top < scroll.offset ||
          bottom > scroll.offset + scroll.position.viewportDimension) {
        scroll.jumpTo(
          (top < scroll.offset
                  ? top
                  : bottom - scroll.position.viewportDimension)
              .clamp(0, scroll.position.maxScrollExtent),
        );
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && turn == ticket && current < widget.items.length) {
        nodes[nodeKey(widget.items[current])]?.requestFocus();
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final node in nodes.values) {
      if (node != widget.entryFocus) node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    controller: scroll,
    itemExtent: 68,
    itemCount: widget.items.length,
    itemBuilder: (context, index) {
      final item = widget.items[index];
      if (nodes.length > 128) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final unused = nodes.entries
              .where(
                (entry) =>
                    entry.value != widget.entryFocus &&
                    entry.value.context == null &&
                    !entry.value.hasFocus,
              )
              .map((e) => e.key)
              .toList();
          for (final key in unused) {
            nodes.remove(key)?.dispose();
          }
        });
      }
      final node = nodes.putIfAbsent(
        nodeKey(item),
        () => index == 0 && widget.entryFocus != null
            ? widget.entryFocus!
            : FocusNode(debugLabel: 'lite title ${item.id}'),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (value) {
            if (value) {
              current = index;
              widget.onFocus?.call(item.id);
            }
          },
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              if (index == 0) {
                widget.up?.call();
              } else {
                unawaited(focus(index - 1));
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              unawaited(focus(index + 1));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                widget.left != null) {
              widget.left!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: LiteMediaTile(
            onRemove: widget.onRemove == null
                ? null
                : () => widget.onRemove!(item),
            focusNode: node,
            title: item.name,
            subtitle:
                widget.subtitle?.call(item) ??
                (item.releaseYear?.toString() ?? ''),
            progress: widget.progress?.call(item),
            icon: item.type == ContentType.series
                ? Icons.tv
                : Icons.movie_outlined,
            onOpen: () async {
              await widget.onOpen(item);
              if (mounted && node.context != null) node.requestFocus();
            },
          ),
        ),
      );
    },
  );
}
