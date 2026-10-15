import 'package:flutter/material.dart';
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
      final Widget content;
      final String phase;
      if (snapshot.connectionState != ConnectionState.done) {
        phase = 'loading';
        content = const Center(child: CircularProgressIndicator());
      } else if (snapshot.hasError) {
        phase = 'error';
        content = EmptyState(safeMessage(snapshot.error!), action: retry);
      } else {
        phase = 'ready';
        content = builder(snapshot.data as T);
      }
      // Network completion is a second transition, independent of navigation.
      return AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(key: ValueKey((future, phase)), child: content),
      );
    },
  );
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

/// Touch, keyboard, and D-pad all use the same focusable interaction.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus, selected;
  final EdgeInsetsGeometry padding;
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.selected = false,
    this.padding = const EdgeInsets.all(14),
  });
  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 120),
    margin: const EdgeInsets.all(4),
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
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: widget.autofocus,
        onFocusChange: (value) => setState(() => focused = value),
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    ),
  );
}
