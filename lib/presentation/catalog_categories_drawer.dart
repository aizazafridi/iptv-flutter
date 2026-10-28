import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

class CatalogCategorySelection {
  final String? id;
  const CatalogCategorySelection(this.id);
}

/// Display-only classification. Unknown conventions retain their original names.
Map<String, List<Category>> groupCatalogCategories(List<Category> categories) {
  final groups = <String, List<Category>>{};
  final seen = <String>{};
  for (final category in categories) {
    if (category.id.trim().isEmpty || !seen.add(category.id)) continue;
    final name = category.name.trim().toUpperCase();
    final group = RegExp(r'^ENGLISH\s*\|\s*FHD\s+(19|20)\d{2}$').hasMatch(name)
        ? 'English FHD'
        : RegExp(r'^ENGLISH\s*\|\s*4K$').hasMatch(name)
        ? '4K'
        : RegExp(r'^ENGLISH\s*\|\s*HINDI DUBBED$').hasMatch(name)
        ? 'Hindi Dubbed'
        : RegExp(r'^ENGLISH\s*\|\s*(19|20)\d{2}\s+CAM$').hasMatch(name)
        ? 'CAM Releases'
        : 'Other Categories';
    groups.putIfAbsent(group, () => []).add(category);
  }
  return {
    for (final name in [
      'English FHD',
      '4K',
      'Hindi Dubbed',
      'CAM Releases',
      'Other Categories',
    ])
      if (groups.containsKey(name)) name: groups[name]!,
  };
}

Future<CatalogCategorySelection?> showCatalogCategoriesDrawer(
  BuildContext context, {
  required List<Category> categories,
  required String allLabel,
  String? selectedId,
}) => showGeneralDialog<CatalogCategorySelection>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close Categories',
  barrierColor: Colors.black38,
  transitionDuration: const Duration(milliseconds: 230),
  transitionBuilder: (_, animation, _, child) => SlideTransition(
    position: Tween(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  ),
  pageBuilder: (_, _, _) => _CategoriesDrawer(
    categories: categories,
    allLabel: allLabel,
    selectedId: selectedId,
  ),
);

class _CategoryRow {
  final String key, label;
  final String? group;
  final Category? category;
  final bool heading;
  const _CategoryRow(
    this.key,
    this.label, {
    this.group,
    this.category,
    this.heading = false,
  });
}

class _CategoriesDrawer extends StatefulWidget {
  final List<Category> categories;
  final String allLabel;
  final String? selectedId;
  const _CategoriesDrawer({
    required this.categories,
    required this.allLabel,
    this.selectedId,
  });
  @override
  State<_CategoriesDrawer> createState() => _CategoriesDrawerState();
}

class _CategoriesDrawerState extends State<_CategoriesDrawer> {
  late final groups = groupCatalogCategories(widget.categories);
  final expanded = <String>{};
  final nodes = <String, FocusNode>{};
  final scroll = ScrollController();
  final close = FocusNode(debugLabel: 'close categories');
  String focused = 'all';
  static const extent = 56.0;
  List<_CategoryRow> get rows => [
    _CategoryRow('all', widget.allLabel),
    for (final entry in groups.entries) ...[
      _CategoryRow(
        'heading:${entry.key}',
        entry.key,
        group: entry.key,
        heading: true,
      ),
      if (expanded.contains(entry.key))
        for (final category in entry.value)
          _CategoryRow(
            'category:${category.id}',
            category.name,
            group: entry.key,
            category: category,
          ),
    ],
  ];
  @override
  void initState() {
    super.initState();
    for (final entry in groups.entries) {
      if (entry.value.any((c) => c.id == widget.selectedId)) {
        expanded.add(entry.key);
        focused = 'category:${widget.selectedId}';
      }
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusRow(rows.indexWhere((r) => r.key == focused)),
    );
  }

  void focusRow(int index) {
    if (!mounted) return;
    if (index < 0) {
      close.requestFocus();
      return;
    }
    final current = rows;
    index = index.clamp(0, current.length - 1);
    focused = current[index].key;
    final key = focused;
    if (scroll.hasClients) {
      final top = index * extent;
      final bottom = top + extent;
      if (top < scroll.offset ||
          bottom > scroll.offset + scroll.position.viewportDimension) {
        scroll.jumpTo(top.clamp(0, scroll.position.maxScrollExtent));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focused == key) nodes[key]?.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void selectRow(_CategoryRow row) {
    if (row.heading) {
      setState(() {
        if (!expanded.remove(row.group)) expanded.add(row.group!);
      });
    } else {
      Navigator.pop(context, CatalogCategorySelection(row.category?.id));
    }
  }

  KeyEventResult key(_CategoryRow row, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final index = rows.indexWhere((r) => r.key == focused);
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      focusRow(index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft && row.group != null) {
      setState(() => expanded.remove(row.group));
      focusRow(rows.indexWhere((r) => r.key == 'heading:${row.group}'));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (row.heading) setState(() => expanded.add(row.group!));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    scroll.dispose();
    close.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = rows;
    final activeId =
        groups.values
            .expand((rows) => rows)
            .any((c) => c.id == widget.selectedId)
        ? widget.selectedId
        : null;
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          key: const ValueKey('catalog-categories-drawer'),
          width: width < 1000 ? width * .48 : width * .34,
          height: double.infinity,
          child: Material(
            color: const Color(0xff1b212b),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Categories',
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Focus(
                        canRequestFocus: false,
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                            focusRow(0);
                            return KeyEventResult.handled;
                          }
                          if (event is KeyDownEvent &&
                              [
                                LogicalKeyboardKey.arrowUp,
                                LogicalKeyboardKey.arrowLeft,
                                LogicalKeyboardKey.arrowRight,
                              ].contains(event.logicalKey)) {
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: IconButton(
                          focusNode: close,
                          tooltip: 'Close Categories',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: scroll,
                      itemExtent: extent,
                      itemCount: current.length,
                      itemBuilder: (context, index) {
                        final row = current[index];
                        final selected =
                            !row.heading && row.category?.id == activeId;
                        final node = nodes.putIfAbsent(
                          row.key,
                          () => FocusNode(debugLabel: row.key),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: (_, event) => key(row, event),
                            child: ListenableBuilder(
                              listenable: node,
                              builder: (_, _) => TextButton(
                                focusNode: node,
                                onPressed: () => selectRow(row),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  alignment: Alignment.centerLeft,
                                  backgroundColor: selected || node.hasFocus
                                      ? const Color(0xff30465d)
                                      : const Color(0xff252e3a),
                                  animationDuration: const Duration(
                                    milliseconds: 160,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: node.hasFocus || selected
                                          ? const Color(0xff64b5f6)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.label,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: row.category != null
                                              ? (width < 1000 ? 11 : 14)
                                              : (width < 1000 ? 13 : 16),
                                          fontWeight: row.heading
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    if (row.heading)
                                      Icon(
                                        expanded.contains(row.group)
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 20,
                                      )
                                    else if (selected)
                                      const Icon(Icons.check, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
