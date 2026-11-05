import '../application/browsing_mode.dart';
import 'live_group_manager.dart';
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
  builder: (context) =>
      liveGroupsTheme(context, _GroupName(groups: groups, group: group)),
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
    builder: (context) => liveGroupsTheme(
      context,
      _Membership(provider: provider, channel: channel),
    ),
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
  late bool general = groups.generalContains(
    widget.channel.id,
    saved: list.contains(widget.channel),
  );
  bool busy = false;
  String? error;
  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await list.saveLiveMembership(widget.channel, selected, general: general);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save. Your selections are kept. Please try again.';
        });
      }
    }
  }

  Future<void> create() async {
    final id = await showLiveGroupName(context, groups);
    if (mounted && id != null) setState(() => selected.add(id));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      backgroundColor: const Color(0xff1b222d),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add to My List',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 5),
          Text(
            'Choose where to save this channel',
            style: TextStyle(fontSize: 13, color: Color(0xffaab8c9)),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height - 230).clamp(180.0, 390.0),
        child: ListenableBuilder(
          listenable: groups,
          builder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (!BrowsingModeSettings.instance.lite) ...[
                    SizedBox.square(
                      dimension: 40,
                      child: ChannelLogo(widget.channel.artwork),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                general || selected.isNotEmpty
                    ? 'All Favorites: Included'
                    : 'All Favorites: Not saved',
                style: const TextStyle(fontSize: 12, color: Color(0xffaab8c9)),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView(
                  children: [
                    LiveGroupRow(
                      label: 'General Favorites',
                      selected: general,
                      autofocus: true,
                      onPressed: busy
                          ? null
                          : () => setState(() => general = !general),
                    ),
                    for (final group in groups.groups)
                      LiveGroupRow(
                        key: ValueKey(group.id),
                        label: group.name,
                        selected: selected.contains(group.id),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                if (!selected.add(group.id)) {
                                  selected.remove(group.id);
                                }
                              }),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: busy ? null : create,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Create New Group'),
              ),
              Text(
                'Saved to ${selected.length} ${selected.length == 1 ? 'group' : 'groups'}',
                style: const TextStyle(fontSize: 12, color: Color(0xffaab8c9)),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            textStyle: const TextStyle(fontSize: 13),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving...' : 'Save to My List'),
        ),
      ],
    ),
  );
}

Widget liveGroupsTheme(BuildContext context, Widget child) => Theme(
  data: Theme.of(context).copyWith(
    colorScheme: const ColorScheme.dark(
      primary: Color(0xff64b5f6),
      onPrimary: Color(0xff0d121b),
      surface: Color(0xff1b222d),
    ),
  ),
  child: child,
);

/// One focus target per row: checked membership and remote focus are separate.
class LiveGroupRow extends StatefulWidget {
  final String label;
  final String? subtitle;
  final bool selected, autofocus;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  const LiveGroupRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
  });
  @override
  State<LiveGroupRow> createState() => _LiveGroupRowState();
}

class _LiveGroupRowState extends State<LiveGroupRow> {
  final own = FocusNode();
  FocusNode get node => widget.focusNode ?? own;
  @override
  void dispose() {
    own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: widget.onKeyEvent,
    child: ListenableBuilder(
      listenable: node,
      builder: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextButton(
          focusNode: node,
          autofocus: widget.autofocus,
          onPressed: widget.onPressed,
          onFocusChange: (value) {
            if (value) {
              Scrollable.ensureVisible(
                context,
                alignment: .5,
                duration: const Duration(milliseconds: 120),
              );
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            backgroundColor: node.hasFocus
                ? const Color(0xff30445d)
                : const Color(0xff252f3d),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
              side: BorderSide(
                color: node.hasFocus
                    ? const Color(0xff64b5f6)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xffaab8c9),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.selected
                    ? Icons.check_circle_outline
                    : Icons.circle_outlined,
                color: widget.selected
                    ? const Color(0xff64b5f6)
                    : Colors.white38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> showLiveGroupManager(
  BuildContext context,
  IptvProvider provider,
) => openLiveGroupManager(context, provider);
