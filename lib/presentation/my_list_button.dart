import 'package:flutter/material.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';

class MyListButton extends StatefulWidget {
  final IptvProvider provider;
  final ContentItem item;
  final bool compact;
  const MyListButton({
    super.key,
    required this.provider,
    required this.item,
    this.compact = false,
  });
  @override
  State<MyListButton> createState() => _MyListButtonState();
}

class _MyListButtonState extends State<MyListButton> {
  late final list = MyList.forProvider(widget.provider);
  final buttonFocus = FocusNode(debugLabel: 'my list action');
  bool busy = true;
  @override
  void dispose() {
    buttonFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    buttonFocus.addListener(() {
      if (buttonFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 120),
              alignment: 0.5,
            );
          }
        });
      }
    });
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
    if (busy) return;
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
      focusNode: buttonFocus,
      tooltip: list.contains(widget.item)
          ? 'Remove from My list'
          : 'Add to My list',
      onPressed: toggle,
      style: myListControlStyle(compact: widget.compact),
      icon: Icon(
        list.contains(widget.item) ? Icons.check_rounded : Icons.add_rounded,
      ),
    ),
  );
}

/// Shared circular outline and remote-focus treatment for detail actions.
ButtonStyle myListControlStyle({bool compact = false}) => ButtonStyle(
  minimumSize: compact ? const WidgetStatePropertyAll(Size(32, 32)) : null,
  padding: compact ? const WidgetStatePropertyAll(EdgeInsets.all(4)) : null,
  iconSize: compact ? const WidgetStatePropertyAll(18) : null,
  tapTargetSize: compact ? MaterialTapTargetSize.shrinkWrap : null,
  shape: const WidgetStatePropertyAll(CircleBorder()),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: const WidgetStatePropertyAll(Colors.white),
  overlayColor: const WidgetStatePropertyAll(Colors.white12),
  side: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.focused)
        ? const BorderSide(color: Colors.white, width: 2)
        : const BorderSide(color: Colors.white54, width: 1.5),
  ),
);
