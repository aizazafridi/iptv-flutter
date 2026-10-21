import 'dart:async';
import 'package:flutter/material.dart';

/// Make existing mouse tooltips available to remote and keyboard navigation.
class FocusTooltips extends StatefulWidget {
  final Widget child;
  const FocusTooltips({super.key, required this.child});
  @override
  State<FocusTooltips> createState() => _FocusTooltipsState();
}

class _FocusTooltipsState extends State<FocusTooltips> {
  Timer? pending;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(focusChanged);
  }

  void focusChanged() {
    pending?.cancel();
    Tooltip.dismissAllToolTips();
    final focused = FocusManager.instance.primaryFocus;
    pending = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || focused != FocusManager.instance.primaryFocus) return;
      final target = focused?.context;
      if (target == null || !target.mounted) return;
      target.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is TooltipState) {
          (element.state as TooltipState).ensureTooltipVisible();
          return false;
        }
        return true;
      });
    });
  }

  @override
  void dispose() {
    pending?.cancel();
    FocusManager.instance.removeListener(focusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
