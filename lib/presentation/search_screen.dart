import 'dart:async';
import '../application/catalog_index.dart';
import 'package:flutter/material.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'details_screen.dart';
import 'widgets.dart';

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
  late final CatalogIndex index;
  List<ContentItem> loadedItems = [];
  Timer? debounce;
  bool indexing = false;
  int generation = 0;

  Future<List<ContentItem>> loadCatalog() async {
    final items = await widget.provider.getAllItems(widget.type);
    if (mounted) {
      loadedItems = items;
      if (query.isNotEmpty) scheduleIndex();
    }
    return items;
  }

  void scheduleIndex() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && query.isNotEmpty && !indexing && loadedItems.isNotEmpty) {
        startIndex();
      }
    });
  }

  Future<void> startIndex({bool retryFailed = false}) async {
    if (indexing || loadedItems.isEmpty) return;
    final token = ++generation;
    setState(() => indexing = true);
    await index.enrich(
      loadedItems,
      cancelled: () => !mounted || token != generation,
      onProgress: () {
        if (mounted && token == generation) setState(() {});
      },
      retryFailed: retryFailed,
    );
    if (mounted && token == generation) setState(() => indexing = false);
  }

  void pauseIndex() {
    generation++;
    debounce?.cancel();
    setState(() => indexing = false);
  }

  Widget indexingStatus() {
    final unique = {
      for (final item in loadedItems) index.key(item): item,
    }.values;
    final total = unique.length;
    final known = unique.where(index.known).length;
    final failed = unique
        .where((item) => index.failed.contains(index.key(item)))
        .length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            indexing
                ? 'Searching actor information: $known of $total titles checked'
                : known == total
                ? 'Title and actor search ready'
                : 'Actor results are incomplete: $known of $total titles checked${failed > 0 ? ' · $failed unavailable' : ''}',
          ),
          if (indexing) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: total == 0 ? null : (known + failed) / total,
            ),
            TextButton(
              onPressed: pauseIndex,
              child: const Text('Pause actor indexing'),
            ),
          ] else if (known < total)
            TextButton(
              onPressed: () => startIndex(retryFailed: true),
              child: Text(
                failed > 0
                    ? 'Retry actor information'
                    : 'Continue actor indexing',
              ),
            ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Load once per search visit, then filter locally without repeated API calls.
    index = CatalogIndex.forProvider(widget.provider);
    catalog = loadCatalog();
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
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
              hintText: 'Search by title or actor across all categories',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        controller.clear();
                        pauseIndex();
                        setState(() => query = '');
                      },
                    ),
            ),
            onChanged: (value) {
              setState(() => query = value.trim().toLowerCase());
              if (query.isEmpty) {
                pauseIndex();
              } else {
                scheduleIndex();
              }
            },
          ),
        ),
        if (query.isNotEmpty && loadedItems.isNotEmpty) indexingStatus(),
        Expanded(
          child: AsyncView(
            future: catalog,
            retry: () => setState(() => catalog = loadCatalog()),
            builder: (items) {
              if (query.isEmpty) {
                return const EmptyState(
                  'Enter a title or actor name to search all categories.',
                );
              }
              final seen = <String>{};
              final results = items.where((item) {
                return index.matches(item, query) && seen.add(item.id);
              }).toList();
              if (results.isEmpty) {
                return EmptyState(
                  indexing
                      ? 'No matches yet. Actor search is still indexing.'
                      : 'No matching titles found.',
                );
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
                            MaterialPageRoute<void>(
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
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name),
                                    if (index.castFor(item).isNotEmpty)
                                      Text(
                                        index.castFor(item),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
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
