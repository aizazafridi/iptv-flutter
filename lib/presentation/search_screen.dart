import 'package:flutter/material.dart';
import 'smooth_page_route.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'details_screen.dart';
import 'widgets.dart';
import 'my_list_button.dart';

/// Search uses the provider contract; the screen never knows API action names.
class CatalogSearchScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  const CatalogSearchScreen({
    super.key,
    required this.provider,
    required this.type,
  });
  @override
  State<CatalogSearchScreen> createState() => _CatalogSearchScreenState();
}

class _CatalogSearchScreenState extends State<CatalogSearchScreen> {
  late Future<List<ContentItem>> catalog;
  final controller = TextEditingController();
  String query = '';
  @override
  void initState() {
    super.initState();
    // Load once per search visit, then filter locally without repeated API calls.
    catalog = widget.provider.getAllItems(widget.type);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Search all ${widget.type.label.toLowerCase()}'),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search titles across all categories',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        setState(() => query = '');
                      },
                    ),
            ),
            onChanged: (value) {
              setState(() => query = value.trim().toLowerCase());
            },
          ),
        ),
        Expanded(
          child: AsyncView(
            future: catalog,
            retry: () => setState(
              () => catalog = widget.provider.getAllItems(widget.type),
            ),
            builder: (items) {
              if (query.isEmpty) {
                return const EmptyState(
                  'Enter a title to search all categories.',
                );
              }
              final terms = query.split(RegExp(r'\s+'));
              final seen = <String>{};
              final results = items.where((item) {
                return terms.every(item.name.toLowerCase().contains) &&
                    seen.add(item.id);
              }).toList();
              if (results.isEmpty) {
                return const EmptyState('No matching titles found.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Text(
                      '${results.length} results across all categories',
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: results.length,
                      itemBuilder: (context, rowIndex) {
                        final item = results[rowIndex];
                        return FocusCard(
                          onTap: () => Navigator.of(context).push(
                            SmoothPageRoute<void>(
                              builder: (_) => DetailsScreen(
                                provider: widget.provider,
                                item: item,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Artwork(item.artwork, width: 52, height: 76),
                              const SizedBox(width: 16),
                              Expanded(child: Text(item.name)),
                              MyListButton(
                                provider: widget.provider,
                                item: item,
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}
