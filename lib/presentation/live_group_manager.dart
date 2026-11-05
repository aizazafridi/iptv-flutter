import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/live_favourite_groups.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'live_favourite_dialogs.dart';
import 'widgets.dart';

Future<void> openLiveGroupManager(
  BuildContext context,
  IptvProvider provider,
) async {
  final groups = LiveFavouriteGroups.forProvider(provider);
  final favourites = await MyList.forProvider(provider).items(ContentType.live);
  await groups.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => liveGroupsTheme(
      context,
      _Manager(provider: provider, initial: favourites),
    ),
  );
}

class _Manager extends StatefulWidget {
  final IptvProvider provider;
  final List<ContentItem> initial;
  const _Manager({required this.provider, required this.initial});
  @override
  State<_Manager> createState() => _ManagerState();
}

class _ManagerState extends State<_Manager> {
  late final groups = LiveFavouriteGroups.forProvider(widget.provider);
  late final list = MyList.forProvider(widget.provider);
  late List<ContentItem> favourites = widget.initial;
  final scroll = ScrollController();
  final nodes = <String, FocusNode>{};
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    list.addListener(refresh);
  }

  void refresh() {
    unawaited(
      list.items(ContentType.live).then((rows) {
        if (mounted) setState(() => favourites = rows);
      }),
    );
  }

  @override
  void dispose() {
    list.removeListener(refresh);
    scroll.dispose();
    for (final n in nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> focus(String id) async {
    final index = groups.groups.indexWhere((g) => g.id == id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (scroll.hasClients && index >= 0) {
        scroll.jumpTo((index * 66.0).clamp(0, scroll.position.maxScrollExtent));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) nodes[id]?.requestFocus();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  Future<void> create() async {
    final id = await showLiveGroupName(context, groups);
    if (mounted && id != null) {
      setState(() {});
      focus(id);
    }
  }

  Future<void> actions(LiveFavouriteGroup group) async {
    if (busy) return;
    final index = groups.groups.indexWhere((g) => g.id == group.id);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: const Color(0xff1b222d),
        title: Text(group.name, style: const TextStyle(fontSize: 20)),
        children: [
          for (final label in [
            'Rename',
            'Move Group',
            'Reorder Channels',
            'Delete Group',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, label),
              child: Text(label),
            ),
        ],
      ),
    );
    if (!mounted) return;
    try {
      switch (choice) {
        case 'Rename':
          await showLiveGroupName(context, groups, group: group);
        case 'Move Group':
          await showDialog<void>(
            context: context,
            builder: (_) => _RemoteOrder(
              title: 'Reorder Groups',
              ids: groups.groups.map((g) => g.id).toList(),
              names: {for (final g in groups.groups) g.id: g.name},
              initialId: group.id,
              save: groups.reorderGroups,
            ),
          );
        case 'Reorder Channels':
          final rows = groups.channels(group.id, favourites);
          await showDialog<void>(
            context: context,
            builder: (_) => _RemoteOrder(
              title: '${group.name}: Reorder Channels',
              ids: rows.map((c) => c.id).toList(),
              names: {for (final c in rows) c.id: c.name},
              save: (ids) => groups.reorderChannels(group.id, ids, favourites),
            ),
          );
        case 'Delete Group':
          final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Delete "${group.name}"?'),
              content: const Text(
                'This removes the group, but does not delete its channels from your provider or other groups. Channels kept in General Favorites remain saved.',
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete Group'),
                ),
              ],
            ),
          );
          if (yes == true) {
            setState(() => busy = true);
            await groups.delete(group.id);
          }
      }
      if (mounted) {
        setState(() {
          busy = false;
          error = null;
        });
        final rows = groups.groups;
        if (rows.isNotEmpty) {
          focus(
            rows.any((g) => g.id == group.id)
                ? group.id
                : rows[index.clamp(0, rows.length - 1)].id,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = safeMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      backgroundColor: const Color(0xff1b222d),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Manage Groups', style: TextStyle(fontSize: 22)),
      content: SizedBox(
        width: 540,
        height: (MediaQuery.sizeOf(context).height - 240).clamp(180.0, 380.0),
        child: ListenableBuilder(
          listenable: groups,
          builder: (_, _) => Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select a group to rename, move, organize or delete.',
                  style: TextStyle(fontSize: 12, color: Color(0xffaab8c9)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: groups.groups.isEmpty
                    ? const Center(child: Text('Create your first group.'))
                    : ListView.builder(
                        controller: scroll,
                        itemExtent: 66,
                        itemCount: groups.groups.length,
                        itemBuilder: (_, index) {
                          final group = groups.groups[index];
                          return LiveGroupRow(
                            key: ValueKey(group.id),
                            label: group.name,
                            subtitle:
                                '${groups.channels(group.id, favourites).length} channels',
                            focusNode: nodes.putIfAbsent(
                              group.id,
                              () => FocusNode(
                                debugLabel: 'manage group ${group.id}',
                              ),
                            ),
                            autofocus: index == 0,
                            onPressed: busy ? null : () => actions(group),
                          );
                        },
                      ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : create,
          child: const Text('Create Group'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// Draft order remains local until OK; Back cancels the current move, not data.
class _RemoteOrder extends StatefulWidget {
  final String title;
  final List<String> ids;
  final Map<String, String> names;
  final String? initialId;
  final Future<void> Function(List<String>) save;
  const _RemoteOrder({
    required this.title,
    required this.ids,
    required this.names,
    required this.save,
    this.initialId,
  });
  @override
  State<_RemoteOrder> createState() => _RemoteOrderState();
}

class _RemoteOrderState extends State<_RemoteOrder> {
  late List<String> draft = List.of(widget.ids), baseline = List.of(widget.ids);
  final nodes = <String, FocusNode>{};
  final scroll = ScrollController();
  String? moving, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialId != null) reveal(widget.initialId!);
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final n in nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void reveal(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = draft.indexOf(id);
      if (scroll.hasClients) {
        scroll.jumpTo((index * 60.0).clamp(0, scroll.position.maxScrollExtent));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) nodes[id]?.requestFocus();
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  void cancel() {
    final id = moving;
    setState(() {
      draft = List.of(baseline);
      moving = null;
      error = null;
    });
    if (id != null) reveal(id);
  }

  Future<void> toggleMove(String id) async {
    if (busy) return;
    if (moving == null) {
      setState(() {
        baseline = List.of(draft);
        moving = id;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (draft.join('\u0000') != baseline.join('\u0000')) {
        await widget.save(List.of(draft));
      }
      if (mounted) {
        setState(() {
          baseline = List.of(draft);
          busy = false;
          moving = null;
        });
        reveal(id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = safeMessage(e);
        });
      }
    }
  }

  KeyEventResult key(String id, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (moving != null &&
        (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack)) {
      if (!busy) cancel();
      return KeyEventResult.handled;
    }
    if (moving != null &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      if (!busy) {
        final index = draft.indexOf(moving!);
        final next =
            (index + (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1))
                .clamp(0, draft.length - 1);
        if (next != index) {
          setState(() {
            final value = draft.removeAt(index);
            draft.insert(next, value);
          });
        }
        reveal(moving!);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => liveGroupsTheme(
    context,
    PopScope(
      canPop: moving == null && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy && moving != null) cancel();
      },
      child: AlertDialog(
        backgroundColor: const Color(0xff1b222d),
        title: Text(widget.title, style: const TextStyle(fontSize: 20)),
        content: SizedBox(
          width: 540,
          height: (MediaQuery.sizeOf(context).height - 240).clamp(160.0, 360.0),
          child: Column(
            children: [
              Text(
                moving == null
                    ? 'Select a row, then press OK to move it.'
                    : 'Moving ${widget.names[moving]} - Up/Down to move, OK to save, Back to cancel',
                style: const TextStyle(fontSize: 12, color: Color(0xff64b5f6)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: draft.isEmpty
                    ? const Center(child: Text('No channels in this group.'))
                    : ListView.builder(
                        controller: scroll,
                        itemExtent: 60,
                        itemCount: draft.length,
                        findChildIndexCallback: (key) => key is ValueKey<String>
                            ? draft.indexOf(key.value)
                            : null,
                        itemBuilder: (_, index) {
                          final id = draft[index];
                          return LiveGroupRow(
                            key: ValueKey(id),
                            label: '${index + 1}. ${widget.names[id] ?? id}',
                            selected: moving == id,
                            focusNode: nodes.putIfAbsent(
                              id,
                              () => FocusNode(debugLabel: 'move row $id'),
                            ),
                            autofocus:
                                id ==
                                (widget.initialId ?? widget.ids.firstOrNull),
                            onKeyEvent: (_, event) => key(id, event),
                            onPressed: busy ? null : () => toggleMove(id),
                          );
                        },
                      ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy
                ? null
                : () {
                    if (moving != null) {
                      cancel();
                    } else {
                      Navigator.pop(context);
                    }
                  },
            child: Text(moving != null ? 'Cancel Move' : 'Done'),
          ),
        ],
      ),
    ),
  );
}
