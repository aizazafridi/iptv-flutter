import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/watch_history.dart';
import '../application/category_locks.dart';
import '../data/video_recordings.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'player_screen.dart';
import 'smooth_page_route.dart';
import 'title_access.dart';
import 'lock_password_dialog.dart';
import 'widgets.dart';

class RecordingsLibraryScreen extends StatefulWidget {
  final IptvProvider provider;
  final ContentType type;
  const RecordingsLibraryScreen({
    super.key,
    required this.provider,
    required this.type,
  });
  @override
  State<RecordingsLibraryScreen> createState() =>
      _RecordingsLibraryScreenState();
}

class _RecordingsLibraryScreenState extends State<RecordingsLibraryScreen> {
  late final store = VideoRecordings.forScope(
    WatchHistory.forProvider(widget.provider).scope,
  );
  late final locks = CategoryLocks.forProvider(widget.provider);
  late Future<void> loading = Future.wait([store.load(), locks.load()]);
  Future<void> play(VideoRecording recording) async {
    if (!await requestTitleAccess(context, widget.provider, recording.item) ||
        !mounted) {
      return;
    }
    final item = recording.item;
    if (item.categoryId != null) {
      final category = Category(item.categoryId!, '', item.type);
      if (locks.isLocked(category)) {
        final pin = await showDialog<String>(
          context: context,
          builder: (_) => LockPasswordDialog(locks: locks),
        );
        if (!mounted || pin == null || !locks.unlock(category, pin)) return;
      }
    }
    final file = await store.file(recording.id);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording file is missing.')),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (_) => PlayerScreen(
          source: PlaybackSource(uri: file.uri, title: recording.title),
        ),
      ),
    );
  }

  Future<void> remove(VideoRecording recording) async {
    try {
      await store.delete(recording);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete recording.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.type.label} recordings')),
    body: AsyncView(
      future: loading,
      retry: () =>
          setState(() => loading = Future.wait([store.load(), locks.load()])),
      builder: (_) => ListenableBuilder(
        listenable: Listenable.merge([store, locks]),
        builder: (_, _) {
          final rows = store.entries
              .where(
                (entry) =>
                    entry.item.type == widget.type &&
                    !locks.titleHidden(entry.item) &&
                    (entry.item.categoryId == null ||
                        !locks.hidden(
                          Category(entry.item.categoryId!, '', entry.item.type),
                        )),
              )
              .toList();
          if (rows.isEmpty) {
            return const EmptyState('No saved recordings for this account.');
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, index) {
              final recording = rows[index];
              return _RecordingRow(
                key: ValueKey(recording.id),
                recording: recording,
                autofocus: index == 0,
                onPlay: () => play(recording),
                onDelete: () => remove(recording),
              );
            },
          );
        },
      ),
    ),
  );
}

class _RecordingRow extends StatefulWidget {
  final VideoRecording recording;
  final bool autofocus;
  final VoidCallback onPlay, onDelete;
  const _RecordingRow({
    super.key,
    required this.recording,
    required this.autofocus,
    required this.onPlay,
    required this.onDelete,
  });
  @override
  State<_RecordingRow> createState() => _RecordingRowState();
}

class _RecordingRowState extends State<_RecordingRow> {
  final playFocus = FocusNode(), deleteFocus = FocusNode();
  @override
  void dispose() {
    playFocus.dispose();
    deleteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          playFocus.hasPrimaryFocus) {
        deleteFocus.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          deleteFocus.hasPrimaryFocus) {
        playFocus.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Row(
      children: [
        Expanded(
          child: FocusCard(
            focusNode: playFocus,
            autofocus: widget.autofocus,
            onTap: widget.onPlay,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recording.title,
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '${widget.recording.created.toLocal().toString().split('.').first}  -  ${(widget.recording.bytes / 1048576).toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        ListenableBuilder(
          listenable: deleteFocus,
          builder: (_, _) => IconButton(
            focusNode: deleteFocus,
            tooltip: 'Delete recording',
            style: IconButton.styleFrom(
              backgroundColor: deleteFocus.hasFocus
                  ? Colors.deepPurple
                  : Colors.transparent,
              foregroundColor: deleteFocus.hasFocus ? Colors.white : null,
              side: deleteFocus.hasFocus
                  ? const BorderSide(color: Colors.white, width: 2)
                  : BorderSide.none,
            ),
            icon: const Icon(Icons.delete_outline),
            onPressed: widget.onDelete,
          ),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );
}
