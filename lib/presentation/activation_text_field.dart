import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Remote focus highlights a field; activation connects the text keyboard.
class ActivationTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final ValueChanged<String>? onChanged, onSubmitted;
  final ValueChanged<bool>? onEditingChanged;
  final bool autofocus, enabled;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp, onNavigateDown;
  const ActivationTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.onEditingChanged,
    this.autofocus = false,
    this.enabled = true,
  });
  @override
  State<ActivationTextField> createState() => ActivationTextFieldState();
}

class ActivationTextFieldState extends State<ActivationTextField> {
  bool editing = false;
  late final focus = widget.focusNode ?? FocusNode();
  void configureFocus() {
    focus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent || editing) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        beginEditing();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (widget.onNavigateDown != null) {
          widget.onNavigateDown!();
        } else {
          node.nextFocus();
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (widget.onNavigateUp != null) {
          widget.onNavigateUp!();
        } else {
          node.previousFocus();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void beginEditing() {
    if (!widget.enabled) return;
    setState(() => editing = true);
    widget.onEditingChanged?.call(true);
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && focus.hasFocus) {
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  void finish({bool submitted = false}) {
    if (!editing) return;
    setState(() => editing = false);
    widget.onEditingChanged?.call(false);
    if (submitted) widget.onSubmitted?.call(widget.controller?.text ?? '');
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  void initState() {
    super.initState();
    configureFocus();
    focus.addListener(focusChanged);
  }

  void focusChanged() {
    if (!focus.hasFocus && editing && mounted) finish();
  }

  @override
  void dispose() {
    focus.removeListener(focusChanged);
    focus.onKeyEvent = null;
    if (widget.focusNode == null) focus.dispose();
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
    onEditingComplete: () => finish(submitted: true),
  );
}
