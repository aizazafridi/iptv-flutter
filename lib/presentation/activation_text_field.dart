import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Remote focus highlights a field; activation connects the text keyboard.
class ActivationTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged;
  final bool autofocus, enabled;
  const ActivationTextField({
    super.key,
    this.controller,
    this.decoration,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });
  @override
  State<ActivationTextField> createState() => _ActivationTextFieldState();
}

class _ActivationTextFieldState extends State<ActivationTextField> {
  bool editing = false;
  late final focus = FocusNode(
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent || editing) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        beginEditing();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        node.nextFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        node.previousFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );
  void beginEditing() {
    if (!widget.enabled) return;
    setState(() => editing = true);
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focus.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void finish() {
    setState(() => editing = false);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus && editing && mounted) finish();
    });
  }

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    focusNode: focus,
    autofocus: widget.autofocus,
    enabled: widget.enabled,
    readOnly: !editing,
    showCursor: editing,
    style: const TextStyle(fontSize: 13),
    decoration: widget.decoration,
    onChanged: widget.onChanged,
    onTap: beginEditing,
    textInputAction: TextInputAction.done,
    onEditingComplete: finish,
  );
}
