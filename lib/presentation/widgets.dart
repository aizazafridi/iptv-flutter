import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';

String safeMessage(Object error) => error is ProviderException
    ? error.message
    : 'Something went wrong. Please retry.';

class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T value) builder;
  final VoidCallback retry;
  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    required this.retry,
  });
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return EmptyState(safeMessage(snapshot.error!), action: retry);
      }
      final transition = ModalRoute.of(context)?.animation;
      if (transition == null) return builder(snapshot.data as T);
      // Build artwork rows after the page animation, rather than during it.
      // Once visible, keep the same child mounted throughout Back navigation.
      return _AfterPageTransition(
        animation: transition,
        builder: () => builder(snapshot.data as T),
      );
    },
  );
}

class _AfterPageTransition extends StatefulWidget {
  final Animation<double> animation;
  final Widget Function() builder;
  const _AfterPageTransition({required this.animation, required this.builder});
  @override
  State<_AfterPageTransition> createState() => _AfterPageTransitionState();
}

class _AfterPageTransitionState extends State<_AfterPageTransition> {
  late bool ready;
  @override
  void initState() {
    super.initState();
    ready = widget.animation.status != AnimationStatus.forward;
    if (!ready) widget.animation.addStatusListener(onStatus);
  }

  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      widget.animation.removeStatusListener(onStatus);
      setState(() => ready = true);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(onStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ready
      ? widget.builder()
      : const Center(child: CircularProgressIndicator());
}

class EmptyState extends StatelessWidget {
  final String message;
  final VoidCallback? action;
  const EmptyState(this.message, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 48,
            color: Color(0xffa49bc3),
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: FilledButton(
                onPressed: action,
                child: const Text('Retry'),
              ),
            ),
        ],
      ),
    ),
  );
}

class Artwork extends StatelessWidget {
  final Uri? uri;
  final Uri? fallbackUri;
  final double? width, height;
  const Artwork(
    this.uri, {
    super.key,
    this.width,
    this.height,
    this.fallbackUri,
  });
  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: width,
      height: height,
      color: const Color(0xff242239),
      child: const Center(
        child: Icon(Icons.movie_outlined, size: 42, color: Color(0xff817c9a)),
      ),
    );
    Widget image(Uri source, {bool fallback = false}) {
      Widget alternative() =>
          !fallback && fallbackUri != null && fallbackUri != source
          ? image(fallbackUri!, fallback: true)
          : placeholder();
      return Image.network(
        source.toString(),
        cacheWidth: 480,
        width: width,
        height: height,
        fit: BoxFit.cover,
        // A stalled thumbnail request may never reach errorBuilder. Keep the
        // series poster visible until the episode image has a decoded frame.
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null ? child : alternative(),
        errorBuilder: (_, _, _) => alternative(),
      );
    }

    final source = uri ?? fallbackUri;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: source == null ? placeholder() : image(source),
    );
  }
}

/// Channel logos keep their proportions instead of filling a poster frame.
class ChannelLogo extends StatelessWidget {
  final Uri? uri;
  const ChannelLogo(this.uri, {super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 64,
      height: 64,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: uri == null
          ? const Icon(Icons.live_tv_rounded, size: 28)
          : Image.network(
              uri.toString(),
              fit: BoxFit.contain,
              cacheWidth: 192,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.live_tv_rounded, size: 28),
            ),
    ),
  );
}

/// Touch, keyboard, and D-pad all use the same focusable interaction.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus, selected;
  final bool revealOnFocus;
  final bool stableSize;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.revealOnFocus = true,
    this.stableSize = false,
    this.focusNode,
    this.selected = false,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  final localFocus = FocusNode();
  FocusNode get cardFocus => widget.focusNode ?? localFocus;
  @override
  void dispose() {
    localFocus.dispose();
    super.dispose();
  }

  KeyEventResult cardKeys(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final actions = cardFocus.descendants.where(
      (node) => node.debugLabel == 'my list action',
    );
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        cardFocus.hasPrimaryFocus &&
        actions.isNotEmpty) {
      actions.first.requestFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        actions.any((node) => node.hasPrimaryFocus)) {
      cardFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: FocusManager.instance,
    builder: (context, _) {
      // Derive styling from current focus, not a flag retained by a reused tile.
      final focused = cardFocus.hasPrimaryFocus;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.all(4),
        padding: EdgeInsets.all(widget.stableSize && !focused ? 2 : 0),
        decoration: BoxDecoration(
          color: widget.selected
              ? const Color(0xff322650)
              : const Color(0xff1b1a2b),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused
                ? const Color(0xffcbb5ff)
                : widget.selected
                ? const Color(0xff7959bd)
                : const Color(0xff302d44),
            width: focused ? 3 : 1,
          ),
        ),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: cardKeys,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              autofocus: widget.autofocus,
              focusNode: cardFocus,
              onFocusChange: (value) {
                if (value && widget.revealOnFocus) {
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
              },
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      );
    },
  );
}
