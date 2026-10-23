import 'package:flutter/material.dart';

/// Constant row geometry keeps remote focus from moving neighbouring categories.
class CategorySidebarItem extends StatefulWidget {
  final String label;
  final bool selected, autofocus, locked;
  final VoidCallback onTap;
  const CategorySidebarItem({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.autofocus = false,
    this.locked = false,
  });
  @override
  State<CategorySidebarItem> createState() => _CategorySidebarItemState();
}

class _CategorySidebarItemState extends State<CategorySidebarItem> {
  final node = FocusNode();
  bool get focused => FocusManager.instance.primaryFocus == node;
  @override
  void dispose() {
    node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FocusManager.instance,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: focused
            ? Colors.white.withValues(alpha: .14)
            : widget.selected
            ? Colors.white.withValues(alpha: .08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          focusNode: node,
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          focusColor: Colors.transparent,
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? Colors.white.withValues(alpha: .06)
                : Colors.transparent,
          ),
          hoverColor: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(6),
          onFocusChange: (value) {
            if (value) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 150),
                alignment: .5,
              );
            }
          },
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: focused
                        ? Colors.white
                        : widget.selected
                        ? Colors.white70
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: focused
                          ? const Color(0xff64b5f6)
                          : widget.selected
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: focused || widget.selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (widget.locked)
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: focused ? Colors.white : Colors.white54,
                  ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
