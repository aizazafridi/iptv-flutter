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
  final scope = FocusNode(debugLabel: 'watch history remote action');
  Timer? timer;
  LogicalKeyboardKey? pressed;
  bool held = false, active = false;

  @override
  void initState() {
    super.initState();
    // Run before a descendant Button/InkWell shortcut activates on key down.
    FocusManager.instance.addEarlyKeyEventHandler(remoteKey);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(remoteKey);
    timer?.cancel();
    scope.dispose();
    super.dispose();
  }

  KeyEventResult remoteKey(KeyEvent event) {
    final key = event.logicalKey;
    if (![
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.gameButtonA,
    ].contains(key)) {
      return KeyEventResult.ignored;
    }
    // The confirmation takes focus while OK is still held. Consume its repeats
    // and release here so the dialog cannot also receive that same activation.
    if (pressed == key) {
      if (event is KeyUpEvent) {
        timer?.cancel();
        final open =
            active &&
            !held &&
            scope.hasFocus &&
            ModalRoute.of(context)?.isCurrent != false;
        pressed = null;
        active = false;
        held = false;
        if (open) widget.onOpen();
      }
      return KeyEventResult.handled;
    }
    if (!scope.hasFocus || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    pressed = key;
    active = true;
    held = false;
    timer = Timer(const Duration(milliseconds: 650), () {
      if (mounted &&
          active &&
          scope.hasFocus &&
          ModalRoute.of(context)?.isCurrent != false) {
        held = true;
        widget.onRemove();
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: scope,
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (!focused) {
        timer?.cancel();
        active = false;
      }
    },
    child: widget.child,
  );
}
