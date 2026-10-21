import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProtectionRow extends StatefulWidget {
  final String name;
  final bool hidden, protected, pinEnabled;
  final VoidCallback onTitle;
  final ValueChanged<bool> onHide, onPin;
  const ProtectionRow({
    super.key,
    required this.name,
    required this.hidden,
    required this.protected,
    required this.pinEnabled,
    required this.onTitle,
    required this.onHide,
    required this.onPin,
  });
  @override
  State<ProtectionRow> createState() => ProtectionRowState();
}

class ProtectionRowState extends State<ProtectionRow> {
  final nodes = List.generate(3, (_) => FocusNode());
  @override
  void dispose() {
    for (final node in nodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget highlight(FocusNode node, Widget child) => ListenableBuilder(
    listenable: node,
    builder: (_, _) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: node.hasFocus ? Colors.white : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    ),
  );
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final index = nodes.indexWhere((node) => node.hasPrimaryFocus);
      if (index > 0 &&
          event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select)) {
        if (index == 1) widget.onHide(!widget.hidden);
        if (index == 2 && widget.pinEnabled) widget.onPin(!widget.protected);
        return KeyEventResult.handled;
      }
      final step = event.logicalKey == LogicalKeyboardKey.arrowRight
          ? 1
          : event.logicalKey == LogicalKeyboardKey.arrowLeft
          ? -1
          : 0;
      if (index < 0 || step == 0) return KeyEventResult.ignored;
      final next = index + step;
      if (next >= 0 && next < (widget.pinEnabled ? 3 : 2)) {
        nodes[next].requestFocus();
      }
      return KeyEventResult.handled;
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              focusNode: nodes[0],
              onPressed: widget.onTitle,
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              child: Text(
                widget.name,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: highlight(
              nodes[1],
              Switch(
                focusNode: nodes[1],
                value: widget.hidden,
                onChanged: widget.onHide,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: highlight(
              nodes[2],
              Switch(
                focusNode: nodes[2],
                value: widget.protected,
                onChanged: widget.pinEnabled ? widget.onPin : null,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
