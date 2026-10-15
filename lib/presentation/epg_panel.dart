import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'system_clock.dart';

class EpgPanel extends StatefulWidget {
  final String channelName;
  final Future<List<EpgProgramme>> Function() load;
  const EpgPanel({super.key, required this.channelName, required this.load});
  @override
  State<EpgPanel> createState() => _EpgPanelState();
}

class _EpgPanelState extends State<EpgPanel> with WidgetsBindingObserver {
  Timer? clockTimer, refreshTimer;
  List<EpgProgramme> entries = [];
  bool loading = true, fetching = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(refresh());
    // Re-read wall-clock time rather than advancing a cached timestamp.
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (fetching) return;
    fetching = true;
    try {
      final result = await widget.load();
      if (mounted) {
        setState(() {
          entries = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not load the programme guide. Please retry.',
        );
      }
    } finally {
      fetching = false;
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clockTimer?.cancel();
    refreshTimer?.cancel();
    super.dispose();
  }

  String time(DateTime date) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(date.toLocal()),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visible = entries.where((p) => p.end.isAfter(now)).toList();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.centerRight,
      insetPadding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Theme(
          data: ThemeData.dark(),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Programme guide',
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh guide',
                    onPressed: fetching ? null : refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Close guide',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                widget.channelName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              const SystemClock(),
              const Divider(),
              if (error != null) Text(error!),
              if (loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No current or upcoming programmes provided for this channel.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final p = visible[index];
                      final current = p.isCurrent(now);
                      final local = p.start.toLocal();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: current ? 0.18 : 0.05,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${current ? "NOW · " : ""}${MaterialLocalizations.of(context).formatShortDate(local)} · ${time(p.start)} – ${time(p.end)}',
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                              ),
                            ),
                            Text(
                              p.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (p.description.isNotEmpty) Text(p.description),
                            if (current)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: LinearProgressIndicator(
                                  value:
                                      (now.difference(p.start).inMilliseconds /
                                              p.end
                                                  .difference(p.start)
                                                  .inMilliseconds)
                                          .clamp(0.0, 1.0),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
