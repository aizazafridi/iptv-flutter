import '../data/locked_provider.dart';
import 'package:flutter/material.dart';
import 'protection_row.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../application/category_locks.dart';
import 'title_lock_settings_screen.dart';
import 'smooth_page_route.dart';
import 'widgets.dart';

class CategoryLockSettingsScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  const CategoryLockSettingsScreen({
    super.key,
    required this.provider,
    this.type = ContentType.live,
  });
  @override
  State<CategoryLockSettingsScreen> createState() =>
      _CategoryLockSettingsScreenState();
}

class _CategoryLockSettingsScreenState
    extends State<CategoryLockSettingsScreen> {
  late final locks = CategoryLocks.forProvider(widget.provider);
  late final raw = widget.provider is LockedProvider
      ? (widget.provider as LockedProvider).delegate
      : widget.provider;
  late Future<List<Category>> categories = load();
  bool busy = false;
  String filter = 'All';
  Future<List<Category>> load() async {
    await locks.load();
    return raw.getCategories(widget.type);
  }

  Future<void> change(
    Category category,
    bool value, {
    bool hide = false,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (hide) {
        await locks.setHidden(category, value);
      } else {
        await locks.configureCategory(category, value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void titles([Category? category]) => Navigator.of(context).push(
    SmoothPageRoute<void>(
      builder: (_) => TitleLockSettingsScreen(
        provider: widget.provider,
        type: widget.type,
        category: category,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.type.label}: category PIN protection',
        style: const TextStyle(fontSize: 18),
      ),
    ),
    body: AsyncView(
      future: categories,
      retry: () => setState(() => categories = load()),
      builder: (rows) => ListenableBuilder(
        listenable: locks,
        builder: (_, _) {
          final filtered = rows
              .where(
                (category) =>
                    filter == 'All' ||
                    (filter == 'PIN protected'
                        ? locks.configured(category)
                        : locks.hidden(category)),
              )
              .toList();
          return Column(
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final option in ['All', 'PIN protected', 'Hidden'])
                    ChoiceChip(
                      label: Text(
                        '$option (${option == 'All' ? rows.length : rows.where((category) => option == 'PIN protected' ? locks.configured(category) : locks.hidden(category)).length})',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: filter == option,
                      onSelected: (_) => setState(() => filter = option),
                    ),
                ],
              ),
              if (!locks.hasPassword)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Set your parental PIN in Settings to enable protection.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Categories', style: TextStyle(fontSize: 13)),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('Hide', textAlign: TextAlign.center),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('PIN', textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, index) {
                    final category = filtered[index];
                    return ProtectionRow(
                      key: ValueKey(category.id),
                      name: category.name,
                      hidden: locks.hidden(category),
                      protected: locks.configured(category),
                      pinEnabled: locks.hasPassword,
                      onTitle: () => titles(category),
                      onHide: (value) => change(category, value, hide: true),
                      onPin: (value) => change(category, value),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
