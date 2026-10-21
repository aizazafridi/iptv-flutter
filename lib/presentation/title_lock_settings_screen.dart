import 'package:flutter/material.dart';
import '../application/category_locks.dart';
import '../data/locked_provider.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'activation_text_field.dart';
import 'widgets.dart';
import 'protection_row.dart';

class TitleLockSettingsScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  final Category? category;
  const TitleLockSettingsScreen({
    super.key,
    required this.provider,
    this.type = ContentType.live,
    this.category,
  });
  @override
  State<TitleLockSettingsScreen> createState() =>
      _TitleLockSettingsScreenState();
}

class _TitleLockSettingsScreenState extends State<TitleLockSettingsScreen> {
  late final locks = CategoryLocks.forProvider(widget.provider);
  late final raw = widget.provider is LockedProvider
      ? (widget.provider as LockedProvider).delegate
      : widget.provider;
  String search = '';
  String filter = 'All';
  bool busy = false;
  late Future<List<ContentItem>> items = load();
  Future<List<ContentItem>> load() async {
    await locks.load();
    return widget.category == null
        ? raw.getAllItems(widget.type)
        : raw.getItems(widget.category!);
  }

  Future<void> change(ContentItem item, bool value, {bool hide = false}) async {
    if (busy) return;
    busy = true;
    try {
      if (hide) {
        await locks.setTitleHidden(item, value);
      } else {
        await locks.configureTitle(item, value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    } finally {
      busy = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.type.label}: title PIN protection',
        style: const TextStyle(fontSize: 18),
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ActivationTextField(
                  decoration: const InputDecoration(
                    hintText: 'Find a title or channel',
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => search = value.toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView(
            future: items,
            retry: () => setState(() => items = load()),
            builder: (rows) => ListenableBuilder(
              listenable: locks,
              builder: (_, _) {
                final results = rows
                    .where(
                      (item) =>
                          item.name.toLowerCase().contains(search) &&
                          (filter == 'All' ||
                              (filter == 'PIN protected'
                                  ? locks.titleConfigured(item)
                                  : locks.titleHidden(item))),
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
                              '$option (${option == 'All' ? rows.length : rows.where((item) => option == 'PIN protected' ? locks.titleConfigured(item) : locks.titleHidden(item)).length})',
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: filter == option,
                            onSelected: (_) => setState(() => filter = option),
                          ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Titles / channels',
                              style: TextStyle(fontSize: 13),
                            ),
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
                      child: results.isEmpty
                          ? const EmptyState('No matching titles or channels')
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (_, index) {
                                final item = results[index];
                                return ProtectionRow(
                                  key: ValueKey(item.id),
                                  name: item.name,
                                  hidden: locks.titleHidden(item),
                                  protected: locks.titleConfigured(item),
                                  pinEnabled: locks.hasPassword,
                                  onTitle: () {
                                    if (locks.hasPassword) {
                                      change(
                                        item,
                                        !locks.titleConfigured(item),
                                      );
                                    }
                                  },
                                  onHide: (value) =>
                                      change(item, value, hide: true),
                                  onPin: (value) => change(item, value),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}
