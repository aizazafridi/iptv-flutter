import 'package:flutter/material.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'details_screen.dart';
import 'player_screen.dart';
import 'widgets.dart';
import 'search_screen.dart';

class BrowseScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  const BrowseScreen({super.key, required this.provider, required this.type});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late Future<List<Category>> categories;
  Future<List<ContentItem>>? items;
  Category? selected;
  String search = '';
  @override
  void initState() {
    super.initState();
    categories = widget.provider.getCategories(widget.type);
  }

  void select(Category category) => setState(() {
    selected = category;
    items = widget.provider.getItems(category);
    search = '';
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: MediaQuery.sizeOf(context).width >= 700 || selected == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        setState(() {
          selected = null;
          items = null;
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.type.label),
        actions: [
          if (widget.type != ContentType.live)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Tooltip(
                message: 'Search all categories',
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: const Icon(Icons.search, size: 28),
                  label: const Text('Search all'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CatalogSearchScreen(
                        provider: widget.provider,
                        type: widget.type,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        leading: BackButton(
          onPressed: () {
            if (MediaQuery.sizeOf(context).width < 700 && selected != null) {
              setState(() {
                selected = null;
                items = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return selected == null ? categoryList() : itemList();
          }
          return Row(
            children: [
              SizedBox(width: 260, child: categoryList()),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? const EmptyState('Choose a category')
                    : itemList(),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget categoryList() => AsyncView(
    future: categories,
    retry: () => setState(() {
      categories = widget.provider.getCategories(widget.type);
    }),
    builder: (rows) => rows.isEmpty
        ? const EmptyState('No categories available')
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            itemBuilder: (_, index) {
              final category = rows[index];
              return FocusCard(
                autofocus: index == 0,
                selected: selected?.id == category.id,
                onTap: () => select(category),
                child: Text(category.name),
              );
            },
          ),
  );

  Widget itemList() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected!.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey(selected!.id),
              decoration: const InputDecoration(
                hintText: 'Search this category',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => search = value.toLowerCase()),
            ),
          ],
        ),
      ),
      Expanded(
        child: AsyncView(
          future: items!,
          retry: () => select(selected!),
          builder: (rows) {
            final filtered = rows
                .where((item) => item.name.toLowerCase().contains(search))
                .toList();
            if (filtered.isEmpty) return const EmptyState('No items found');
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 285,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final item = filtered[index];
                return FocusCard(
                  autofocus: index == 0,
                  onTap: () => openItem(item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: Artwork(item.artwork),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> openItem(ContentItem item) async {
    if (item.type != ContentType.live) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailsScreen(provider: widget.provider, item: item),
        ),
      );
      return;
    }
    try {
      final source = await widget.provider.resolvePlayback(item);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerScreen(source: source)),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    }
  }
}
