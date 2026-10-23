import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import '../application/category_locks.dart';
import 'activation_text_field.dart';
import 'system_clock.dart';
import 'widgets.dart';

/// Guide rows request schedules only as they enter the viewport.
class TvGuideScreen extends StatefulWidget {
  final IptvProvider provider;
  const TvGuideScreen({super.key, required this.provider});
  @override
  State<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends State<TvGuideScreen> {
  late Future<List<ContentItem>> channels = load();
  final schedules = <String, Future<List<EpgProgramme>>>{};
  final controller = TextEditingController();
  String query = '';
  Timer? clock;
  int clockTicks = 0;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {
          if (++clockTicks % 4 == 0) schedules.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<List<ContentItem>> load() async {
    final locks = CategoryLocks.forProvider(widget.provider);
    await locks.load();
    final rows = await widget.provider.getAllItems(ContentType.live);
    return rows
        .where(
          (item) =>
              !locks.titleHidden(item) &&
              !locks.titleLocked(item) &&
              (item.categoryId == null ||
                  !locks.hidden(
                        Category(item.categoryId!, '', ContentType.live),
                      ) &&
                      !locks.isLocked(
                        Category(item.categoryId!, '', ContentType.live),
                      )),
        )
        .toList();
  }

  Future<List<EpgProgramme>> schedule(ContentItem item) =>
      schedules.putIfAbsent(item.id, () async {
        final p = widget.provider;
        if (p is! EpgProvider) return [];
        final now = DateTime.now();
        final rows = await (p as EpgProvider).getEpg(item);
        return rows.where((row) => row.end.isAfter(now)).take(8).toList();
      });
  String time(DateTime value) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(value.toLocal()),
        alwaysUse24HourFormat: true,
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('TV Guide'),
      actions: [
        const SystemClock(),
        IconButton(
          tooltip: 'Refresh guide',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {
            schedules.clear();
            channels = load();
          }),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ActivationTextField(
            controller: controller,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search channels',
            ),
            onChanged: (value) =>
                setState(() => query = value.toLowerCase().trim()),
          ),
        ),
        Expanded(
          child: AsyncView(
            future: channels,
            retry: () => setState(() => channels = load()),
            builder: (rows) {
              final visible = rows
                  .where((item) => item.name.toLowerCase().contains(query))
                  .toList();
              if (visible.isEmpty) {
                return const Center(child: Text('No channels available'));
              }
              return ListView.builder(
                itemCount: visible.length,
                itemExtent: 84,
                itemBuilder: (context, index) {
                  final item = visible[index];
                  return Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: .12),
                          width: .7,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 160,
                          child: Text(
                            item.name,
                            maxLines: 3,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FutureBuilder<List<EpgProgramme>>(
                            future: schedule(item),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return TextButton(
                                  onPressed: () =>
                                      setState(() => schedules.remove(item.id)),
                                  child: const Text('Retry guide'),
                                );
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                );
                              }
                              final entries = snapshot.data!;
                              if (entries.isEmpty) {
                                return const Text(
                                  'Programme guide unavailable',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                );
                              }
                              return ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: entries.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 24),
                                itemBuilder: (context, index) {
                                  final entry = entries[index];
                                  final current = entry.isCurrent(
                                    DateTime.now(),
                                  );
                                  final elapsed = current
                                      ? DateTime.now()
                                                .difference(entry.start)
                                                .inMilliseconds /
                                            entry.end
                                                .difference(entry.start)
                                                .inMilliseconds
                                      : 0.0;
                                  return SizedBox(
                                    width: 230,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        alignment: Alignment.topLeft,
                                        backgroundColor: Colors.transparent,
                                        shape: const RoundedRectangleBorder(),
                                        side: BorderSide.none,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 5,
                                        ),
                                      ),
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(entry.title),
                                          content: SingleChildScrollView(
                                            child: Text(
                                              '${MaterialLocalizations.of(context).formatShortDate(entry.start.toLocal())}  ${time(entry.start)} - ${time(entry.end)}\n\n${entry.description}',
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Close'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${current ? 'NOW  ' : ''}${time(entry.start)} - ${time(entry.end)}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: current
                                                  ? Colors.lightBlueAccent
                                                  : Colors.white54,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            entry.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                          if (current) ...[
                                            const SizedBox(height: 6),
                                            LinearProgressIndicator(
                                              value: elapsed.clamp(0.0, 1.0),
                                              minHeight: 3,
                                              color: Colors.lightBlueAccent,
                                              backgroundColor: Colors.white12,
                                              semanticsLabel:
                                                  'Current programme progress',
                                              semanticsValue:
                                                  '${(elapsed * 100).round()}%',
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
