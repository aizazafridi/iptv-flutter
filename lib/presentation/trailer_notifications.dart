import 'dart:async';
import 'package:flutter/material.dart';
import '../application/trailer_reminders.dart';
import '../application/recent_catalog_cache.dart';
import '../application/category_locks.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../data/trailers_repository.dart';
import 'trailers_screen.dart';

class TrailerNotifications extends StatefulWidget {
  final IptvProvider provider;
  final FocusNode? focusNode;
  const TrailerNotifications({
    super.key,
    required this.provider,
    this.focusNode,
  });
  @override
  State<TrailerNotifications> createState() => _TrailerNotificationsState();
}

class _TrailerNotificationsState extends State<TrailerNotifications>
    with WidgetsBindingObserver {
  late final reminders = TrailerReminders.forProvider(widget.provider);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reminders.addListener(changed);
    unawaited(check());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> check() async {
    try {
      final locks = CategoryLocks.forProvider(widget.provider);
      await locks.load();
      if (!mounted || locks.kidsProfile) return;
      await reminders.checkDates();
      final cached = RecentCatalogCache.peekAll(
        widget.provider,
        ContentType.movies,
      );
      if (cached != null) {
        await reminders.checkCatalog(widget.provider, await cached);
      }
    } catch (_) {
      /* Retry at next startup, resume, or catalogue refresh. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  @override
  void dispose() {
    reminders.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> open() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notifications'),
        content: SizedBox(
          width: 650,
          height: 360,
          child: reminders.notices.isEmpty
              ? const Center(child: Text('No notifications yet'))
              : ListView(
                  children: [
                    for (final notice in reminders.notices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: const Color(0xff202b3c),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.notifications_active_outlined,
                                  color: Color(0xff9acaff),
                                  size: 30,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notice.available
                                            ? 'Now Available'
                                            : 'Movie Release Reminder',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        notice.message,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    TrailerMovieDetailsScreen(
                                                      provider: widget.provider,
                                                      movie: notice.movie,
                                                      repository:
                                                          TrailersRepository
                                                              .configured,
                                                      reminders: reminders,
                                                    ),
                                              ),
                                            ),
                                        child: const Text(
                                          'View Movie Details',
                                          style: TextStyle(
                                            color: Color(0xff9acaff),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    try {
      await reminders.markRead();
    } catch (_) {
      /* Keep unread indicator if persistence fails. */
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    focusNode: widget.focusNode,
    key: const ValueKey('dashboard-reminder-notifications'),
    tooltip: 'Notifications (${reminders.unread} unread)',
    onPressed: open,
    icon: Badge(
      isLabelVisible: reminders.unread > 0,
      label: Text('${reminders.unread}'),
      child: const Icon(Icons.notifications_none),
    ),
  );
}
