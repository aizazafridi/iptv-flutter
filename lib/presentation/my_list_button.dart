import 'package:flutter/material.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';

class MyListButton extends StatefulWidget {
  final IptvProvider provider;
  final ContentItem item;
  const MyListButton({super.key, required this.provider, required this.item});
  @override
  State<MyListButton> createState() => _MyListButtonState();
}

class _MyListButtonState extends State<MyListButton> {
  late final list = MyList.forProvider(widget.provider);
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await list.load();
    } catch (_) {
      /* Report storage errors when the user tries saving. */
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> toggle() async {
    setState(() => busy = true);
    try {
      await list.toggle(widget.item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save My list. Please retry.'),
          ),
        );
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: list,
    builder: (_, _) => IconButton(
      tooltip: list.contains(widget.item)
          ? 'Remove from My list'
          : 'Add to My list',
      onPressed: busy ? null : toggle,
      icon: Icon(
        list.contains(widget.item)
            ? Icons.bookmark
            : Icons.bookmark_add_outlined,
      ),
    ),
  );
}
