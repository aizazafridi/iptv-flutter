import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';

class LiveNowPlaying extends StatefulWidget {
  final Future<List<EpgProgramme>> Function() load;
  const LiveNowPlaying({super.key, required this.load});
  @override
  State<LiveNowPlaying> createState() => _LiveNowPlayingState();
}

class _LiveNowPlayingState extends State<LiveNowPlaying> {
  List<EpgProgramme> entries = [];
  Timer? timer;
  bool fetching = false;
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    if (fetching) return;
    fetching = true;
    try {
      final result = await widget.load();
      if (mounted) setState(() => entries = result);
    } catch (_) {
      /* Missing EPG must not interrupt playback. */
    } finally {
      fetching = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = entries
        .where((entry) => entry.isCurrent(DateTime.now()))
        .firstOrNull;
    if (current == null) return const SizedBox.shrink();
    final localizations = MaterialLocalizations.of(context);
    String time(DateTime value) =>
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()));
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.live_tv, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Now: ${current.title}  (${time(current.start)} - ${time(current.end)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
