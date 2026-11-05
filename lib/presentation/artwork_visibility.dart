import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../application/browsing_mode.dart';

/// Gate metadata lookups as well as image bytes: off-screen cards do no work.
class ArtworkVisibility extends StatefulWidget {
  final Widget Function(BuildContext, bool) builder;
  const ArtworkVisibility({super.key, required this.builder});
  @override
  State<ArtworkVisibility> createState() => _ArtworkVisibilityState();
}

class _ArtworkVisibilityState extends State<ArtworkVisibility> {
  ScrollPosition? horizontal, vertical;
  bool visible = false, scheduled = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    horizontal?.removeListener(check);
    vertical?.removeListener(check);
    horizontal = Scrollable.maybeOf(context, axis: Axis.horizontal)?.position;
    vertical = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    horizontal?.addListener(check);
    vertical?.addListener(check);
    check();
  }

  @override
  void initState() {
    super.initState();
    BrowsingModeSettings.instance.addListener(check);
  }

  void check() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      var viewport = Offset.zero & MediaQuery.sizeOf(context);
      var offstage = false;
      context.visitAncestorElements((element) {
        final render = element.renderObject;
        if (render is RenderOffstage && render.offstage) offstage = true;
        if (render is RenderAbstractViewport &&
            render is RenderBox &&
            (render as RenderBox).hasSize) {
          final parent = render as RenderBox;
          viewport = viewport.intersect(
            parent.localToGlobal(Offset.zero) & parent.size,
          );
        }
        return true;
      });
      final next =
          !BrowsingModeSettings.instance.lite &&
          !offstage &&
          !viewport.isEmpty &&
          viewport.overlaps(box.localToGlobal(Offset.zero) & box.size);
      if (next != visible) setState(() => visible = next);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    horizontal?.removeListener(check);
    vertical?.removeListener(check);
    BrowsingModeSettings.instance.removeListener(check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    check();
    return widget.builder(context, visible);
  }
}
