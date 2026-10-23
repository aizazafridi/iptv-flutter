import '../application/category_locks.dart';
import 'package:flutter/material.dart';
import 'compact_player_panel_theme.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import 'widgets.dart';

class ChannelPicker extends StatefulWidget {
  final String title;
  final bool categoriesFirst;
  final bool embedded;
  final VoidCallback? onClose;
  final String? currentId, categoryId;
  final IptvProvider? provider;
  final Future<bool> Function(ContentItem)? onSelect;
  final Future<List<ContentItem>> Function() load;
  const ChannelPicker({
    super.key,
    required this.title,
    required this.load,
    this.categoriesFirst = false,
    this.embedded = false,
    this.onClose,
    this.currentId,
    this.categoryId,
    this.provider,
    this.onSelect,
  });
  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<ChannelPicker> {
  late Future<List<ContentItem>> channels;
  late bool showingCategories =
      widget.categoriesFirst && widget.provider != null;
  late Future<List<Category>> categoryRequest;
  late String? selectedId = widget.currentId;
  List<Category> categories = [];
  int categoryIndex = -1;
  late String title = widget.title;
  final scroll = ScrollController();
  final nodes = <String, FocusNode>{};
  bool busy = false;
  DateTime? lastActivation;
  String? lastId;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    categoryRequest = fetchCategories();
    channels = showingCategories
        ? Future.value(<ContentItem>[])
        : load(
            () => widget.provider != null && widget.categoryId != null
                ? widget.provider!.getItems(
                    Category(
                      widget.categoryId!,
                      widget.title,
                      ContentType.live,
                    ),
                  )
                : widget.load(),
          );
    if (!showingCategories) loadCategories();
  }

  Future<List<Category>> fetchCategories() async {
    final provider = widget.provider;
    if (provider == null) return [];
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    final rows = await provider.getCategories(ContentType.live);
    return rows.where((category) => !locks.hidden(category)).toList();
  }

  void openCategory(Category category, List<Category> rows) {
    setState(() {
      categories = rows;
      categoryIndex = rows.indexOf(category);
      title = category.name;
      showingCategories = false;
      channels = load(() async {
        final items = await widget.provider!.getItems(category);
        final locks = CategoryLocks.forProvider(widget.provider!);
        return items.where((item) => !locks.titleHidden(item)).toList();
      });
    });
  }

  Future<void> loadCategories() async {
    try {
      final result = await categoryRequest;
      if (mounted) {
        setState(() {
          categories = result;
          categoryIndex = result.indexWhere(
            (category) => category.id == widget.categoryId,
          );
          if (categoryIndex >= 0) title = result[categoryIndex].name;
        });
      }
    } catch (_) {
      /* The initial channel list still works without categories. */
    }
  }

  Future<List<ContentItem>> load(
    Future<List<ContentItem>> Function() request,
  ) async {
    revision++;
    return request();
  }

  int restoredRevision = -1;
  void restoreCurrent(List<ContentItem> rows) {
    if (restoredRevision == revision || rows.isEmpty) return;
    restoredRevision = revision;
    final version = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || version != revision || !scroll.hasClients) return;
      final found = rows.indexWhere((row) => row.id == selectedId);
      final index = found < 0 ? 0 : found;
      scroll.jumpTo((index * 52.0).clamp(0, scroll.position.maxScrollExtent));
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && version == revision) nodes[rows[index].id]?.requestFocus();
    });
  }

  void changeCategory(int direction) {
    if (categories.isEmpty || busy) return;
    final next = (categoryIndex + direction) % categories.length;
    setState(() {
      categoryIndex = next;
      title = categories[next].name;
      channels = load(() => widget.provider!.getItems(categories[next]));
    });
  }

  Future<void> selectChannel(ContentItem channel) async {
    if (busy) return;
    final now = DateTime.now();
    if (lastId == channel.id &&
        lastActivation != null &&
        now.difference(lastActivation!) < const Duration(milliseconds: 650)) {
      Navigator.pop(context);
      return;
    }
    if (widget.onSelect == null) {
      Navigator.pop(context, channel);
      return;
    }
    if (channel.id != selectedId) {
      setState(() => busy = true);
      final success = await widget.onSelect!(channel);
      if (!mounted) return;
      setState(() {
        if (success) selectedId = channel.id;
        busy = false;
      });
      if (!success) return;
    }
    lastId = channel.id;
    lastActivation = DateTime.now();
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final node in nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      width: widget.embedded ? double.infinity : 280,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: compactPlayerPanelTheme(),
        child: Column(
          children: [
            if (widget.onClose != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close channel selection',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ),
            if (showingCategories)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${widget.title} - Categories',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            if (widget.categoriesFirst &&
                widget.provider != null &&
                !showingCategories)
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Categories'),
                onPressed: () => setState(() => showingCategories = true),
              ),
            if (!showingCategories)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous category',
                    onPressed: categories.isEmpty || busy
                        ? null
                        : () => changeCategory(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next category',
                    onPressed: categories.isEmpty || busy
                        ? null
                        : () => changeCategory(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            if (busy) const LinearProgressIndicator(),
            const Divider(),
            Expanded(
              child: showingCategories
                  ? AsyncView<List<Category>>(
                      future: categoryRequest,
                      retry: () =>
                          setState(() => categoryRequest = fetchCategories()),
                      builder: (rows) => rows.isEmpty
                          ? const Center(child: Text('No categories available'))
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (_, index) => Material(
                                color: Colors.transparent,
                                child: ListTile(
                                  autofocus: index == 0,
                                  title: Text(rows[index].name),
                                  trailing: const Icon(
                                    Icons.chevron_right,
                                    size: 18,
                                  ),
                                  onTap: () => openCategory(rows[index], rows),
                                ),
                              ),
                            ),
                    )
                  : AsyncView(
                      future: channels,
                      retry: () => setState(
                        () => channels = load(
                          categoryIndex < 0
                              ? widget.load
                              : () => widget.provider!.getItems(
                                  categories[categoryIndex],
                                ),
                        ),
                      ),
                      builder: (rows) {
                        restoreCurrent(rows);
                        return rows.isEmpty
                            ? const Center(child: Text('No channels available'))
                            : ListView.builder(
                                controller: scroll,
                                itemExtent: 52,
                                itemCount: rows.length,
                                itemBuilder: (_, index) {
                                  final channel = rows[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      focusNode: nodes.putIfAbsent(
                                        channel.id,
                                        () => FocusNode(),
                                      ),
                                      selected: channel.id == selectedId,
                                      selectedTileColor: Colors.white
                                          .withValues(alpha: .18),
                                      leading: SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: ChannelLogo(channel.artwork),
                                      ),
                                      title: Text(
                                        channel.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: channel.id == selectedId
                                          ? const Icon(Icons.play_arrow)
                                          : null,
                                      onTap: () => selectChannel(channel),
                                    ),
                                  );
                                },
                              );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (widget.embedded) return panel;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.centerLeft,
      insetPadding: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
      child: panel,
    );
  }
}
