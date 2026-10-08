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
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return EmptyState(safeMessage(snapshot.error!), action: retry);
      }
      return builder(snapshot.data as T);
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
  final double? width, height;
  const Artwork(this.uri, {super.key, this.width, this.height});
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: uri == null
          ? placeholder()
          : Image.network(
              uri.toString(),
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder(),
            ),
    );
  }
}

/// Touch, keyboard, and D-pad all use the same focusable interaction.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus, selected;
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.autofocus = false,
    this.selected = false,
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
        child: Padding(padding: const EdgeInsets.all(14), child: widget.child),
      ),
    ),
  );
}
