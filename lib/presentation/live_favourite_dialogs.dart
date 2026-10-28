import 'package:flutter/material.dart';
import '../application/live_favourite_groups.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'widgets.dart';

Future<String?> showLiveGroupName(
  BuildContext context,
  LiveFavouriteGroups groups, {
  LiveFavouriteGroup? group,
}) => showDialog<String>(
  context: context,
  builder: (_) => _GroupName(groups: groups, group: group),
);

class _GroupName extends StatefulWidget {
  final LiveFavouriteGroups groups;
  final LiveFavouriteGroup? group;
  const _GroupName({required this.groups, this.group});
  @override
  State<_GroupName> createState() => _GroupNameState();
}

class _GroupNameState extends State<_GroupName> {
  late final text = TextEditingController(text: widget.group?.name ?? '');
  String? error;
  bool busy = false;
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = widget.group == null
          ? await widget.groups.create(text.text)
          : await widget.groups
                .rename(widget.group!.id, text.text)
                .then((_) => widget.group!.id);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = safeMessage(e);
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.group == null ? 'New Group' : 'Rename Group'),
    content: SizedBox(
      width: 340,
      child: TextField(
        controller: text,
        autofocus: true,
        maxLength: 40,
        decoration: InputDecoration(labelText: 'Group name', errorText: error),
        onSubmitted: (_) {
          if (!busy) save();
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: busy ? null : save, child: const Text('Save')),
    ],
  );
}

Future<void> showLiveFavouriteDialog(
  BuildContext context,
  IptvProvider provider,
  ContentItem channel,
) async {
  final groups = LiveFavouriteGroups.forProvider(provider);
  final list = MyList.forProvider(provider);
  await Future.wait([groups.load(), list.load()]);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _Membership(provider: provider, channel: channel),
  );
}

class _Membership extends StatefulWidget {
  final IptvProvider provider;
  final ContentItem channel;
  const _Membership({required this.provider, required this.channel});
  @override
  State<_Membership> createState() => _MembershipState();
}

class _MembershipState extends State<_Membership> {
  late final groups = LiveFavouriteGroups.forProvider(widget.provider);
  late final list = MyList.forProvider(widget.provider);
  late final selected = groups.memberships(widget.channel.id);
  late final original = Set<String>.of(selected);
  late bool favorite = list.contains(widget.channel);
  bool busy = false;
  String? error;
  Future<void> save() async {
    if (!favorite && original.length > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove from all groups?'),
          content: const Text(
            'This channel will be removed from All Favorites and every custom group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await groups.assign(widget.channel.id, favorite ? selected : {});
      try {
        if (list.contains(widget.channel) != favorite) {
          await list.toggle(widget.channel);
        }
      } catch (_) {
        await groups.assign(widget.channel.id, original);
        rethrow;
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not save changes. Your selections are kept. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Add to My List', style: TextStyle(fontSize: 20)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: groups,
            builder: (_, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox.square(
                      dimension: 42,
                      child: ChannelLogo(widget.channel.artwork),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(widget.channel.name)),
                  ],
                ),
                CheckboxListTile(
                  autofocus: true,
                  title: const Text('All Favorites'),
                  value: favorite,
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          favorite = value!;
                          if (!favorite) selected.clear();
                        }),
                ),
                for (final group in groups.groups)
                  CheckboxListTile(
                    title: Text(group.name),
                    value: selected.contains(group.id),
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            if (value!) {
                              selected.add(group.id);
                              favorite = true;
                            } else {
                              selected.remove(group.id);
                            }
                          }),
                  ),
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => showLiveGroupName(context, groups),
                  icon: const Icon(Icons.add),
                  label: const Text('Create New Group'),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving?' : 'Save Changes'),
        ),
      ],
    ),
  );
}

Future<void> showLiveGroupManager(
  BuildContext context,
  IptvProvider provider,
) async {
  final groups = LiveFavouriteGroups.forProvider(provider);
  final favorites = await MyList.forProvider(provider).items(ContentType.live);
  await groups.load();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) {
        Future<void> action(Future<void> Function() operation) async {
          try {
            await operation();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Could not save groups. Please retry.'),
                ),
              );
            }
          }
        }

        return AlertDialog(
          title: const Text('Manage Groups'),
          content: SizedBox(
            width: 520,
            height: 300,
            child: ListenableBuilder(
              listenable: groups,
              builder: (_, _) => ListView(
                children: [
                  ListTile(
                    title: const Text('All Favorites'),
                    subtitle: Text('${favorites.length} channels'),
                  ),
                  for (final group in groups.groups)
                    ListTile(
                      title: Text(group.name),
                      subtitle: Text(
                        '${groups.channels(group.id, favorites).length} channels',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Rename ${group.name}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => showLiveGroupName(
                              context,
                              groups,
                              group: group,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Move ${group.name} up',
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: groups.groups.first.id == group.id
                                ? null
                                : () => action(
                                    () => groups.moveGroup(group.id, -1),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Move ${group.name} down',
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: groups.groups.last.id == group.id
                                ? null
                                : () => action(
                                    () => groups.moveGroup(group.id, 1),
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Delete ${group.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Delete ${group.name}?'),
                                  content: const Text(
                                    'Channels stay in All Favorites and other groups.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) {
                                await action(() => groups.delete(group.id));
                              }
                            },
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
              onPressed: () => showLiveGroupName(context, groups),
              child: const Text('+ New Group'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
}
