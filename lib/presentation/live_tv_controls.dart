import 'live_favourite_dialogs.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'widgets.dart';
import 'activation_text_field.dart';
import '../application/my_list.dart';
import '../domain/iptv_provider.dart';

class LiveChannelStrip extends StatefulWidget {
  final Future<List<ContentItem>> Function() load;
  final String? currentId;
  final Future<void> Function(ContentItem) onSelect;
  final bool autofocus;
  const LiveChannelStrip({
    super.key,
    required this.load,
    required this.currentId,
    required this.onSelect,
    this.autofocus = false,
  });
  @override
  State<LiveChannelStrip> createState() => _LiveChannelStripState();
}

class _LiveChannelStripState extends State<LiveChannelStrip> {
  late Future<List<ContentItem>> rows = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<ContentItem>>(
    future: rows,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox(
          height: 88,
          child: Center(
            child: Text('Loading channels...', style: TextStyle(fontSize: 12)),
          ),
        );
      }
      final all = snapshot.data!;
      final index = all.indexWhere((item) => item.id == widget.currentId);
      final start = index < 0 ? 0 : (index - 3).clamp(0, all.length);
      final visible = all.skip(start).take(12).toList();
      return SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final item = visible[i];
            return SizedBox(
              width: 140,
              child: _LiveTile(
                autofocus:
                    widget.autofocus &&
                    (item.id == widget.currentId || index < 0 && i == 0),
                onTap: () => widget.onSelect(item),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 36,
                      child: ChannelLogo(item.artwork),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class LiveTvControls extends StatefulWidget {
  final ContentItem? channel;
  final String title;
  final IptvProvider? provider;
  final Future<List<EpgProgramme>> Function() loadGuide;
  final Future<List<ContentItem>> Function()? loadChannels;
  final Future<void> Function(ContentItem) onSwitch;
  final VoidCallback onChannels, onGuide, onActivity, onOverlayOpened;
  final VoidCallback? onAspect, onVolume;
  final bool muted;
  final VoidCallback? onRecord, onSplit, onCatchUp;
  final Widget? health;
  final bool playing, recording;
  final FocusNode primaryFocus;
  const LiveTvControls({
    super.key,
    this.channel,
    required this.title,
    this.provider,
    required this.loadGuide,
    this.loadChannels,
    required this.onSwitch,
    required this.onChannels,
    required this.onGuide,
    required this.onActivity,
    required this.onOverlayOpened,
    this.onAspect,
    this.onVolume,
    this.muted = false,
    this.onRecord,
    this.onSplit,
    this.onCatchUp,
    this.health,
    required this.playing,
    required this.recording,
    required this.primaryFocus,
  });
  @override
  State<LiveTvControls> createState() => _LiveTvControlsState();
}

class _LiveTvControlsState extends State<LiveTvControls> {
  List<EpgProgramme> entries = [];
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    final provider = widget.provider;
    if (provider != null) {
      final list = MyList.forProvider(provider);
      list.addListener(favoritesChanged);
      unawaited(list.load().catchError((Object _) {}));
    }
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final rows = await widget.loadGuide();
      if (mounted) setState(() => entries = rows);
    } catch (_) {}
  }

  void favoritesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.provider != null) {
      MyList.forProvider(widget.provider!).removeListener(favoritesChanged);
    }
    timer?.cancel();
    super.dispose();
  }

  String time(DateTime date) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(date.toLocal()));
  Widget action(
    String title,
    Widget icon,
    VoidCallback? onTap, {
    FocusNode? focus,
  }) {
    final label = switch (title) {
      'Search channels' => 'Search',
      'Split screen' => 'Multiview',
      'Mute' || 'Unmute' => 'Audio',
      'Add to My list' || 'Remove from My list' => 'My List',
      _ => title,
    };
    return Tooltip(
      message: title,
      child: TextButton(
        focusNode: focus,
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 64)),
          maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 64)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          animationDuration: const Duration(milliseconds: 150),
          iconSize: const WidgetStatePropertyAll(20),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.white30
                : states.contains(WidgetState.focused)
                ? const Color(0xff151c26)
                : const Color(0xffd5dde8),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const Color(0xffe9eff6)
                : const Color(0xff252f3b),
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.white12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        onPressed: onTap == null
            ? null
            : () {
                widget.onActivity();
                onTap();
              },
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> toggleFavorite() async {
    final provider = widget.provider;
    final channel = widget.channel;
    if (provider == null || channel == null) return;
    try {
      widget.onOverlayOpened();
      await showLiveFavouriteDialog(context, provider, channel);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save My List. Please retry.'),
          ),
        );
      }
    }
  }

  Future<void> search() async {
    widget.onOverlayOpened();
    final channels = widget.loadChannels!();
    var query = '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Search channels'),
          content: SizedBox(
            width: 420,
            height: 320,
            child: Column(
              children: [
                ActivationTextField(
                  decoration: const InputDecoration(
                    hintText: 'Search channels',
                  ),
                  onChanged: (value) => update(() => query = value),
                ),
                Expanded(
                  child: FutureBuilder<List<ContentItem>>(
                    future: channels,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Could not load channels. Please retry.'),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final matches = snapshot.data!
                          .where(
                            (item) => item.name.toLowerCase().contains(
                              query.toLowerCase(),
                            ),
                          )
                          .toList();
                      return ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(matches[index].name),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSwitch(matches[index]);
                          },
                        ),
                      );
                    },
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
      ),
    );
    if (mounted) widget.onActivity();
  }

  @override
  Widget build(BuildContext context) {
    final favorite =
        widget.provider != null &&
        widget.channel != null &&
        MyList.forProvider(widget.provider!).contains(widget.channel!);
    final now = DateTime.now();
    final current = entries.where((p) => p.isCurrent(now)).firstOrNull;
    final next = entries.where((p) => p.start.isAfter(now)).firstOrNull;
    final progress = current == null
        ? null
        : now.difference(current.start).inMilliseconds /
              current.end.difference(current.start).inMilliseconds;
    return Listener(
      onPointerDown: (_) => widget.onActivity(),
      onPointerMove: (_) => widget.onActivity(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xe6000000), Colors.black],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 68,
                        child: ChannelLogo(widget.channel?.artwork),
                      ),
                      if (widget.health != null) ...[
                        const SizedBox(height: 6),
                        FittedBox(fit: BoxFit.scaleDown, child: widget.health!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current?.title ?? widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        current == null
                            ? widget.title
                            : '${time(current.start)} - ${time(current.end)}   ${current.end.difference(now).inMinutes + 1} min left   ${widget.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                      if (current?.description.isNotEmpty == true)
                        Text(
                          current!.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      if (next != null)
                        Text(
                          'Next  ${time(next.start)} - ${time(next.end)}   ${next.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress ?? 0,
              minHeight: 3,
              color: const Color(0xff64b5f6),
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 7),
            LayoutBuilder(
              builder: (context, constraints) {
                final controls = [
                  action(
                    'Channels',
                    const Icon(Icons.playlist_play_outlined),
                    widget.onChannels,
                    focus: widget.primaryFocus,
                  ),
                  action(
                    'TV Guide',
                    const Icon(Icons.calendar_view_day_outlined),
                    widget.onGuide,
                  ),
                  action(
                    'Search channels',
                    const Icon(Icons.search),
                    widget.loadChannels == null ? null : search,
                  ),
                  action(
                    widget.recording ? 'Stop recording' : 'Record',
                    const Icon(
                      Icons.radio_button_checked,
                      color: Colors.redAccent,
                    ),
                    widget.onRecord,
                  ),
                  action(
                    'Split screen',
                    const Icon(Icons.grid_view_rounded),
                    widget.onSplit,
                  ),
                  action(
                    'Aspect ratio',
                    const Icon(Icons.picture_in_picture_outlined),
                    widget.onAspect,
                  ),
                  action(
                    widget.muted ? 'Unmute' : 'Mute',
                    Icon(
                      widget.muted
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                    ),
                    widget.onVolume,
                  ),
                  action(
                    'Catch-up',
                    const Icon(Icons.history),
                    widget.onCatchUp,
                  ),
                  action(
                    favorite ? 'Remove from My list' : 'Add to My list',
                    Icon(
                      favorite ? Icons.check : Icons.add,
                      color: Colors.white,
                    ),
                    widget.provider != null && widget.channel != null
                        ? toggleFavorite
                        : null,
                  ),
                ];
                final minimumWidth = controls.length * 76.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: constraints.maxWidth < minimumWidth
                        ? minimumWidth
                        : constraints.maxWidth,
                    child: Row(
                      children: controls
                          .map(
                            (control) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: control,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool autofocus;
  const _LiveTile({
    required this.child,
    required this.onTap,
    this.autofocus = false,
  });
  @override
  State<_LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<_LiveTile> {
  bool focused = false;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOut,
    decoration: BoxDecoration(
      color: focused ? const Color(0xff3b536a) : const Color(0xff242c34),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(
        color: focused ? Colors.white : Colors.transparent,
        width: 2,
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: widget.autofocus,
        onTap: widget.onTap,
        onFocusChange: (value) {
          setState(() => focused = value);
          if (value) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 150),
            );
          }
        },
        child: Padding(padding: const EdgeInsets.all(8), child: widget.child),
      ),
    ),
  );
}
