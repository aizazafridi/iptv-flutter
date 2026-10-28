import 'live_favourite_dialogs.dart';
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

  Future<void> create() async {
    final id = await showLiveGroupName(context, groups);
    if (mounted && id != null) widget.onGroupChanged(id);
  }

  Future<void> assign(ContentItem channel) =>
      showLiveFavouriteDialog(context, widget.provider, channel);

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
      await assign(channel);
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

  Future<void> manage() => showLiveGroupManager(context, widget.provider);

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
