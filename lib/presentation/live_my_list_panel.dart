import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/live_favourite_groups.dart';
import '../application/my_list.dart';
import '../application/category_locks.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../data/locked_provider.dart';
import 'activation_text_field.dart';
import 'widgets.dart';

class LiveMyListPanel extends StatefulWidget {
  final IptvProvider provider;
  final ValueChanged<ContentItem> onPlay;
  final ValueChanged<String> onGroupChanged;
  final String selectedGroup;
  const LiveMyListPanel({
    super.key,
    required this.provider,
    required this.onPlay,
    required this.onGroupChanged,
    this.selectedGroup = LiveFavouriteGroups.all,
  });
  @override
  State<LiveMyListPanel> createState() => _LiveMyListPanelState();
}

class _LiveMyListPanelState extends State<LiveMyListPanel> {
  late final groups = LiveFavouriteGroups.forProvider(widget.provider);
  late final list = MyList.forProvider(widget.provider);
  late final locks = CategoryLocks.forProvider(widget.provider);
  late Future<List<ContentItem>> loading = load();
  String search = '';
  Future<List<ContentItem>> load() async {
    await groups.load();
    final rows = await list.items(ContentType.live);
    return widget.provider is LockedProvider
        ? (widget.provider as LockedProvider).visibleSavedItems(rows)
        : locks.visibleItems(rows);
  }

  @override
  void initState() {
    super.initState();
    list.addListener(reload);
    locks.addListener(reload);
  }

  void reload() {
    if (mounted) setState(() => loading = load());
  }

  @override
  void dispose() {
    list.removeListener(reload);
    locks.removeListener(reload);
    super.dispose();
  }

  Future<void> action(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeMessage(error))));
      }
    }
  }

  Future<String?> groupName({String? current}) => showDialog<String>(
    context: context,
    builder: (_) => _GroupNameDialog(current: current),
  );

  Future<void> create() async {
    final name = await groupName();
    if (!mounted || name == null) return;
    await action(() async {
      final id = await groups.create(name);
      if (mounted) widget.onGroupChanged(id);
    });
  }

  Future<void> assign(ContentItem channel) async {
    final selected = groups.memberships(channel.id);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            'Groups: ${channel.name}',
            style: const TextStyle(fontSize: 16),
          ),
          content: SizedBox(
            width: 340,
            child: groups.groups.isEmpty
                ? const Text('Create a group using New group first.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final group in groups.groups)
                          CheckboxListTile(
                            dense: true,
                            title: Text(group.name),
                            value: selected.contains(group.id),
                            onChanged: (value) => update(() {
                              if (value == true) {
                                selected.add(group.id);
                              } else {
                                selected.remove(group.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await action(() => groups.assign(channel.id, selected));
    }
  }

  Future<void> channelMenu(
    ContentItem channel,
    String group,
    List<ContentItem> favourites,
  ) async {
    final option = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(channel.name, style: const TextStyle(fontSize: 16)),
        children: [
          for (final entry in {
            'groups': 'Choose groups',
            'up': 'Move up',
            'down': 'Move down',
            'remove': 'Remove from My List',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || option == null) return;
    if (option == 'groups') {
      await assign(channel);
    } else if (option == 'remove') {
      await action(() => list.toggle(channel));
    } else {
      await action(
        () => groups.moveChannel(
          group,
          channel.id,
          option == 'up' ? -1 : 1,
          favourites,
        ),
      );
    }
  }

  Future<void> manage() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage groups', style: TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 460,
          height: 330,
          child: ListenableBuilder(
            listenable: groups,
            builder: (_, _) => groups.groups.isEmpty
                ? const Center(child: Text('No custom groups yet.'))
                : ListView(
                    children: [
                      for (final group in groups.groups)
                        ListTile(
                          key: ValueKey(group.id),
                          dense: true,
                          title: Text(
                            group.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Rename ${group.name}',
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () async {
                                  final name = await groupName(
                                    current: group.name,
                                  );
                                  if (mounted && name != null) {
                                    await action(
                                      () => groups.rename(group.id, name),
                                    );
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Move ${group.name} up',
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                onPressed: () => action(
                                  () => groups.moveGroup(group.id, -1),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Move ${group.name} down',
                                icon: const Icon(
                                  Icons.arrow_downward,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    action(() => groups.moveGroup(group.id, 1)),
                              ),
                              IconButton(
                                tooltip: 'Delete ${group.name}',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    action(() => groups.delete(group.id)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted && !groups.exists(widget.selectedGroup)) {
      widget.onGroupChanged(LiveFavouriteGroups.all);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncView(
    future: loading,
    retry: reload,
    builder: (favourites) => ListenableBuilder(
      listenable: groups,
      builder: (_, _) {
        final selected = groups.exists(widget.selectedGroup)
            ? widget.selectedGroup
            : LiveFavouriteGroups.all;
        final rows = groups
            .channels(selected, favourites)
            .where((item) => item.name.toLowerCase().contains(search))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My List',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'New group',
                    onPressed: create,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 22,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Manage groups',
                    onPressed: manage,
                    icon: const Icon(Icons.folder_copy_outlined, size: 22),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 130),
                child: SingleChildScrollView(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final id in [
                          LiveFavouriteGroups.all,
                          LiveFavouriteGroups.ungrouped,
                          ...groups.groups.map((group) => group.id),
                        ])
                          ChoiceChip(
                            key: ValueKey('group-$id'),
                            label: Text(
                              '${groups.name(id)} (${groups.channels(id, favourites).length})',
                              style: const TextStyle(fontSize: 13),
                            ),
                            selected: selected == id,
                            onSelected: (_) => widget.onGroupChanged(id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ActivationTextField(
                decoration: const InputDecoration(
                  hintText: 'Search this group',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                onChanged: (value) =>
                    setState(() => search = value.toLowerCase()),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      'No channels in this group. Add favourites, then use Choose groups to organize them.',
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, index) {
                        final channel = rows[index];
                        return _ChannelRow(
                          key: ValueKey(channel.id),
                          channel: channel,
                          autofocus: index == 0,
                          onPlay: () => widget.onPlay(channel),
                          onOrganize: () =>
                              channelMenu(channel, selected, favourites),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _ChannelRow extends StatefulWidget {
  final ContentItem channel;
  final bool autofocus;
  final VoidCallback onPlay, onOrganize;
  const _ChannelRow({
    super.key,
    required this.channel,
    required this.autofocus,
    required this.onPlay,
    required this.onOrganize,
  });
  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  final play = FocusNode(), organize = FocusNode();
  @override
  void dispose() {
    play.dispose();
    organize.dispose();
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
          play.hasPrimaryFocus) {
        organize.requestFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          organize.hasPrimaryFocus) {
        play.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Row(
      children: [
        Expanded(
          child: FocusCard(
            focusNode: play,
            autofocus: widget.autofocus,
            onTap: widget.onPlay,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ChannelLogo(widget.channel.artwork),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.channel.name,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          focusNode: organize,
          tooltip: 'Organize ${widget.channel.name}',
          onPressed: widget.onOrganize,
          icon: const Icon(Icons.more_vert),
        ),
      ],
    ),
  );
}

class _GroupNameDialog extends StatefulWidget {
  final String? current;
  const _GroupNameDialog({this.current});
  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final controller = TextEditingController(text: widget.current ?? '');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.current == null ? 'New group' : 'Rename group'),
    content: SizedBox(
      width: 300,
      child: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Group name'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}
