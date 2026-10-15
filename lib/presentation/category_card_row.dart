import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'widgets.dart';

/// Rows load only when visible; horizontal lists build posters on demand.
class CategoryCardRow extends StatefulWidget {
  final String title;
  final Widget? headerAction;
  final Widget Function(ContentItem item)? itemAction;
  final Future<List<ContentItem>> Function(bool refresh) load;
  final VoidCallback onMore;
  final void Function(ContentItem) onOpen;
  const CategoryCardRow({
    super.key,
    required this.title,
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
  @override
  void initState() {
    super.initState();
    items = widget.load(false);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void move(int direction) {
    if (!scroll.hasClients) return;
    final target =
        (scroll.offset + direction * scroll.position.viewportDimension * 0.8)
            .clamp(0.0, scroll.position.maxScrollExtent);
    scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
              IconButton(
                tooltip: 'Scroll ${widget.title} left',
                onPressed: () => move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Scroll ${widget.title} right',
                onPressed: () => move(1),
                icon: const Icon(Icons.chevron_right),
              ),
              if (widget.headerAction != null) widget.headerAction!,
              TextButton(onPressed: widget.onMore, child: const Text('All')),
            ],
          ),
        ),
        SizedBox(
          height: 270,
          child: AsyncView(
            future: items,
            retry: () => setState(() => items = widget.load(true)),
            builder: (rows) => rows.isEmpty
                ? const EmptyState('No items available')
                : ListView.builder(
                    controller: scroll,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final item = rows[index];
                      return SizedBox(
                        width: 180,
                        child: FocusCard(
                          onTap: () => widget.onOpen(item),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SizedBox(
                                  width: double.infinity,
                                  child: Artwork(item.artwork),
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
          ),
        ),
      ],
    ),
  );
}
