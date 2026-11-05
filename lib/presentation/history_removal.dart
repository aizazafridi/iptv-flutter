import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/watch_history.dart';
import '../domain/models.dart';

Future<void> confirmHistoryRemoval(
  BuildContext context,
  WatchHistory history,
  ContentItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove from watch history?'),
      content: Text('Remove "${item.name}" from watch history?'),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await history.removeTitle(item);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to remove title. Please try again.'),
        ),
      );
    }
  }
}

/// Remote OK is committed on release so a held OK never also starts playback.
class HistoryRemoteAction extends StatefulWidget {
  final Widget child;
  final VoidCallback onOpen, onRemove;
  const HistoryRemoteAction({
    super.key,
    required this.child,
    required this.onOpen,
    required this.onRemove,
  });
  @override
  State<HistoryRemoteAction> createState() => _HistoryRemoteActionState();
}

class _HistoryRemoteActionState extends State<HistoryRemoteAction> {
  Timer? timer;
  bool held = false, active = false;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (!focused) {
        timer?.cancel();
        active = false;
      }
    },
    onKeyEvent: (_, event) {
      if (![
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.numpadEnter,
      ].contains(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent && !active) {
        active = true;
        held = false;
        timer = Timer(const Duration(milliseconds: 650), () {
          if (mounted && active) {
            held = true;
            widget.onRemove();
          }
        });
      } else if (event is KeyUpEvent && active) {
        timer?.cancel();
        active = false;
        if (!held) widget.onOpen();
      }
      return KeyEventResult.handled;
    },
    child: widget.child,
  );
}
