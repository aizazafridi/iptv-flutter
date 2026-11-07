import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import '../application/category_locks.dart';
import 'activation_text_field.dart';
import 'system_clock.dart';
import 'widgets.dart';

const guidePixelsPerMinute = 3.2;
double guideDurationWidth(Duration duration) =>
    duration.inMilliseconds / 60000 * guidePixelsPerMinute;

class TvGuideScreen extends StatefulWidget {
  final IptvProvider provider;
  final bool activePreview;
  final ContentItem? previewChannel;
  final bool previewLoading;
  final Future<bool> Function(ContentItem)? onTune;
  final VoidCallback? onWatchPreview;
  final VoidCallback? onClose;
  const TvGuideScreen({
    super.key,
    required this.provider,
    this.activePreview = false,
    this.previewChannel,
    this.previewLoading = false,
    this.onTune,
    this.onWatchPreview,
    this.onClose,
  });
  @override
  State<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends State<TvGuideScreen> {
  late Future<List<ContentItem>> channels = load();
  final refreshFocus = FocusNode(debugLabel: 'guide refresh');
  final searchFocus = FocusNode(debugLabel: 'guide search');
  final categoryNodes = <String, FocusNode>{};
  final channelNodes = <String, FocusNode>{};
  final vertical = ScrollController();
  final categoryScroll = ScrollController();
  List<Category> categories = [];
  List<ContentItem> displayed = [];
  String? categoryId;
  bool initializedCategory = false;
  bool initialFocusPending = true;
  FocusNode categoryNode(String id) => categoryNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'guide category $id'),
  );
  FocusNode channelNode(String id) => channelNodes.putIfAbsent(
    id,
    () => FocusNode(debugLabel: 'guide channel $id'),
  );
  void focusCategory() {
    channelFocusVersion++;
    final id = categoryId ?? '';
    final node = categoryNode(id);
    if (node.context != null) {
      node.requestFocus();
      Scrollable.ensureVisible(
        node.context!,
        duration: const Duration(milliseconds: 150),
      );
      return;
    }
    // The selected category may not be built yet in the horizontal lazy list.
    final index = id.isEmpty ? 0 : categories.indexWhere((c) => c.id == id) + 1;
    if (categoryScroll.hasClients) {
      categoryScroll.jumpTo(
        (index * 150.0).clamp(0, categoryScroll.position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void moveCategory(String id, int delta) {
    final ids = ['', ...categories.map((c) => c.id)];
    final index = (ids.indexOf(id) + delta).clamp(0, ids.length - 1);
    final node = categoryNode(ids[index]);
    if (node.context != null) {
      node.requestFocus();
      return;
    }
    if (categoryScroll.hasClients) {
      categoryScroll.jumpTo(
        (index * 150.0).clamp(0, categoryScroll.position.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  int channelFocusVersion = 0;
  String? focusedChannelId;
  void focusChannel([int index = 0]) {
    if (displayed.isEmpty) {
      focusCategory();
      return;
    }
    final targetIndex = index.clamp(0, displayed.length - 1);
    final id = displayed[targetIndex].id;
    final version = ++channelFocusVersion;
    if (vertical.hasClients) {
      final start = targetIndex * 52.0;
      final position = vertical.position;
      final target = start < position.pixels
          ? start
          : start + 52 > position.pixels + position.viewportDimension
          ? start + 52 - position.viewportDimension
          : position.pixels;
      if ((target - position.pixels).abs() > .5) {
        vertical.jumpTo(target.clamp(0, position.maxScrollExtent));
      }
    }
    final node = channelNode(id);
    if (node.context != null) node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          version == channelFocusVersion &&
          displayed.any((c) => c.id == id)) {
        channelNode(id).requestFocus();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> channelFocused(ContentItem item) async {
    focusedChannelId = item.id;
    try {
      final entries = await schedule(item);
      if (!mounted ||
          focusedChannelId != item.id ||
          !channelNode(item.id).hasFocus) {
        return;
      }
      final programme =
          entries.where((p) => p.isCurrent(DateTime.now())).firstOrNull ??
          entries.firstOrNull;
      selection.value = programme == null ? null : (item, programme);
    } catch (_) {
      if (mounted && focusedChannelId == item.id) selection.value = null;
    }
  }

  KeyEventResult navigate(KeyEvent event, VoidCallback up, VoidCallback down) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      up();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      down();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  final schedules = <String, Future<List<EpgProgramme>>>{};
  // Bound EPG work so guide loading does not flood the active live connection.
  final epgLanes = <Future<void>>[Future.value(), Future.value()];
  int nextEpgLane = 0;
  final controller = TextEditingController();
  final horizontal = ScrollController();
  final offset = ValueNotifier<double>(0);
  final selection = ValueNotifier<(ContentItem, EpgProgramme)?>(null);
  late final windowStart = DateTime.fromMillisecondsSinceEpoch(
    DateTime.now().millisecondsSinceEpoch ~/ 1800000 * 1800000,
    isUtc: true,
  ).subtract(const Duration(minutes: 30));
  late final windowEnd = windowStart.add(const Duration(hours: 6));
  final timelineWidth = guideDurationWidth(const Duration(hours: 6));
  late ContentItem? tunedChannel = widget.previewChannel;
  bool tuning = false;
  String? activatedChannel;
  DateTime? activatedAt;
  Future<void>? pendingTune;
  Future<void> activateChannel(ContentItem channel) async {
    final now = DateTime.now();
    final doubleEnter =
        activatedChannel == channel.id &&
        activatedAt != null &&
        now.difference(activatedAt!) < const Duration(milliseconds: 500);
    activatedChannel = channel.id;
    activatedAt = now;
    if (doubleEnter) {
      activatedAt = null;
      await pendingTune;
      if (mounted && tunedChannel?.id == channel.id) {
        widget.onWatchPreview?.call();
      }
      return;
    }
    if (!tuning && widget.onTune != null) {
      pendingTune = tune(channel);
      await pendingTune;
    }
  }

  Future<void> tune(ContentItem channel) async {
    if (tuning || widget.onTune == null) return;
    setState(() => tuning = true);
    try {
      if (!await widget.onTune!(channel) || !mounted) return;
      setState(() => tunedChannel = channel);
      selection.value = null;
      try {
        final rows = await schedule(channel);
        if (!mounted) return;
        final programme = rows
            .where((p) => p.isCurrent(DateTime.now()))
            .firstOrNull;
        if (programme != null) selection.value = (channel, programme);
      } catch (_) {
        /* Playing the channel does not require a guide. */
      }
    } finally {
      if (mounted) setState(() => tuning = false);
    }
  }

  String query = '';
  Timer? clock;
  @override
  void initState() {
    super.initState();
    horizontal.addListener(() => offset.value = horizontal.offset);
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    refreshFocus.dispose();
    searchFocus.dispose();
    vertical.dispose();
    categoryScroll.dispose();
    for (final node in [...categoryNodes.values, ...channelNodes.values]) {
      node.dispose();
    }
    controller.dispose();
    horizontal.dispose();
    offset.dispose();
    selection.dispose();
    super.dispose();
  }

  Future<List<ContentItem>> load() async {
    final locks = CategoryLocks.forProvider(widget.provider);
    await locks.load();
    final rows = await widget.provider.getAllItems(ContentType.live);
    final visible = rows
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
    final available = await widget.provider.getCategories(ContentType.live);
    categories = available
        .where((c) => !locks.hidden(c) && !locks.isLocked(c))
        .toList();
    if (!initializedCategory) {
      categoryId =
          visible
              .where((c) => c.id == widget.previewChannel?.id)
              .firstOrNull
              ?.categoryId ??
          widget.previewChannel?.categoryId;
      if (!categories.any((c) => c.id == categoryId)) categoryId = null;
      initializedCategory = true;
    }
    // Promote the playing channel without changing the provider's remaining order.
    final current = visible.indexWhere(
      (item) => item.id == widget.previewChannel?.id,
    );
    if (current > 0) visible.insert(0, visible.removeAt(current));
    return visible;
  }

  Future<List<EpgProgramme>> schedule(ContentItem item) =>
      schedules.putIfAbsent(item.id, () async {
        final p = widget.provider;
        if (p is! EpgProvider) return [];
        final lane = nextEpgLane++ % epgLanes.length;
        final request = epgLanes[lane].then((_) async {
          if (!mounted) return <EpgProgramme>[];
          return (p as EpgProvider).getEpg(item);
        });
        epgLanes[lane] = request.then<void>((_) {}, onError: (Object _) {});
        final rows = await request;
        return rows
            .where(
              (row) =>
                  row.end.isAfter(windowStart) && row.start.isBefore(windowEnd),
            )
            .toList();
      });

  String time(DateTime value) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(value.toLocal()),
        alwaysUse24HourFormat: true,
      );
  void select(
    ContentItem channel,
    EpgProgramme programme,
    double left,
    double width,
  ) {
    selection.value = (channel, programme);
    if (!horizontal.hasClients) return;
    final viewport = horizontal.position.viewportDimension;
    final target = left < horizontal.offset
        ? left
        : left + width > horizontal.offset + viewport
        ? left + width - viewport
        : horizontal.offset;
    horizontal.animateTo(
      target.clamp(0, horizontal.position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Widget programmeDetails(ContentItem channel, EpgProgramme p) => AlertDialog(
    title: Text(p.title),
    content: SingleChildScrollView(
      child: Text(
        '${channel.name}\n${time(p.start)} - ${time(p.end)}\n\n${p.description}',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
  Widget previewHeader() => SizedBox(
    height: 136,
    child: Row(
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width * .30).clamp(160, 350),
          height: 136,
          child: widget.activePreview
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onWatchPreview,
                    child: Tooltip(
                      message: 'Watch channel fullscreen',
                      child: Stack(
                        children: [
                          const Positioned.fill(child: SizedBox.expand()),
                          if (widget.previewLoading || tuning)
                            const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          const Positioned(
                            right: 8,
                            bottom: 8,
                            child: Icon(
                              Icons.fullscreen,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const ColoredBox(
                  color: Color(0xff252c36),
                  child: Center(
                    child: Icon(
                      Icons.tv_outlined,
                      size: 32,
                      color: Colors.white54,
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: ValueListenableBuilder<(ContentItem, EpgProgramme)?>(
            valueListenable: selection,
            builder: (context, selected, _) {
              if (selected == null) {
                return Text(
                  tunedChannel?.name ?? 'Select a programme',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                );
              }
              final (channel, p) = selected;
              final now = DateTime.now();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${channel.name} - LIVE TV',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff9bc7ff),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${time(p.start)} - ${time(p.end)}',
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  if (p.isCurrent(now)) ...[
                    const SizedBox(height: 7),
                    LinearProgressIndicator(
                      value:
                          now.difference(p.start).inMilliseconds /
                          p.end.difference(p.start).inMilliseconds,
                      minHeight: 4,
                      color: const Color(0xff529cff),
                      backgroundColor: Colors.white24,
                    ),
                  ],
                  const SizedBox(height: 7),
                  Expanded(
                    child: Text(
                      p.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
  Widget timelineRow(ContentItem item, int index) => Row(
    children: [
      Container(
        width: 160,
        height: 49,
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: const Color(0xff1d242c),
        child: Material(
          color: Colors.transparent,
          child: Focus(
            onKeyEvent: (_, event) => navigate(
              event,
              () => index == 0 ? focusCategory() : focusChannel(index - 1),
              () => focusChannel(index + 1),
            ),
            child: InkWell(
              key: ValueKey('guide-channel:${item.id}'),
              focusNode: channelNode(item.id),
              onFocusChange: (focused) {
                if (focused) unawaited(channelFocused(item));
              },
              focusColor: const Color(0xff365777),
              onTap: () {
                unawaited(activateChannel(item));
              },
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 28,
                    child: ChannelLogo(item.artwork),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<EpgProgramme>>(
          future: schedule(item),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  schedules.remove(item.id);
                }),
                child: const Text('Retry guide'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return const Text(
                'Programme guide unavailable',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              );
            }
            if (selection.value == null &&
                (tunedChannel == null || tunedChannel!.id == item.id)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    selection.value == null &&
                    (tunedChannel == null || tunedChannel!.id == item.id)) {
                  selection.value = (
                    item,
                    entries
                            .where((e) => e.isCurrent(DateTime.now()))
                            .firstOrNull ??
                        entries.first,
                  );
                }
              });
            }
            return ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: timelineWidth,
                maxWidth: timelineWidth,
                child: ValueListenableBuilder<double>(
                  valueListenable: offset,
                  builder: (context, x, _) => Transform.translate(
                    offset: Offset(-x, 0),
                    child: SizedBox(
                      width: timelineWidth,
                      height: 49,
                      child: Stack(
                        children: [
                          for (final p in entries)
                            if (p.end.isAfter(windowStart) &&
                                p.start.isBefore(windowEnd))
                              Positioned(
                                left: guideDurationWidth(
                                  p.start.difference(windowStart),
                                ).clamp(0, timelineWidth),
                                top: 0,
                                bottom: 0,
                                width: guideDurationWidth(
                                  (p.end.isAfter(windowEnd) ? windowEnd : p.end)
                                      .difference(
                                        p.start.isBefore(windowStart)
                                            ? windowStart
                                            : p.start,
                                      ),
                                ),
                                child: _ProgrammeCell(
                                  key: ValueKey(
                                    'programme:${item.id}:${p.title}',
                                  ),
                                  programme: p,
                                  time: '${time(p.start)} - ${time(p.end)}',
                                  onFocus: () => select(
                                    item,
                                    p,
                                    guideDurationWidth(
                                      p.start.difference(windowStart),
                                    ).clamp(0, timelineWidth),
                                    guideDurationWidth(
                                      p.end.difference(p.start),
                                    ),
                                  ),
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => programmeDetails(item, p),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Roboto'),
    ),
    child: Scaffold(
      backgroundColor: widget.activePreview
          ? Colors.transparent
          : const Color(0xff101419),
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: const Color(0xff101419),
        leading: BackButton(
          onPressed: widget.onClose ?? () => Navigator.pop(context),
        ),
        title: const Text(
          'TV Guide',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          const SystemClock(),
          Focus(
            onKeyEvent: (_, event) =>
                navigate(event, () {}, () => searchFocus.requestFocus()),
            child: IconButton(
              focusNode: refreshFocus,
              tooltip: 'Refresh guide',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                schedules.clear();
                channels = load();
              }),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: previewHeader(),
          ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xff101419),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const Divider(color: Colors.white24, height: 1),
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          const Text(
                            'TV GUIDE',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xff9bc7ff),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: ActivationTextField(
                              controller: controller,
                              focusNode: searchFocus,
                              onNavigateUp: () => refreshFocus.requestFocus(),
                              onNavigateDown: focusCategory,
                              decoration: const InputDecoration(
                                hintText: 'Search channels',
                                isDense: true,
                                border: InputBorder.none,
                              ),
                              onChanged: (value) => setState(
                                () => query = value.toLowerCase().trim(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: FutureBuilder<List<ContentItem>>(
                        future: channels,
                        builder: (context, snapshot) => ListView(
                          controller: categoryScroll,
                          itemExtent: 150,
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final category in [
                              const Category('', 'All', ContentType.live),
                              ...categories,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 8,
                                  bottom: 6,
                                ),
                                child: Focus(
                                  onFocusChange: (focused) {
                                    if (focused) {
                                      final ctx = categoryNode(
                                        category.id,
                                      ).context;
                                      if (ctx != null) {
                                        Scrollable.ensureVisible(
                                          ctx,
                                          duration: const Duration(
                                            milliseconds: 150,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  canRequestFocus: false,
                                  onKeyEvent: (_, event) {
                                    if (event is KeyDownEvent ||
                                        event is KeyRepeatEvent) {
                                      if (event.logicalKey ==
                                              LogicalKeyboardKey.arrowLeft ||
                                          event.logicalKey ==
                                              LogicalKeyboardKey.arrowRight) {
                                        moveCategory(
                                          category.id,
                                          event.logicalKey ==
                                                  LogicalKeyboardKey.arrowRight
                                              ? 1
                                              : -1,
                                        );
                                        return KeyEventResult.handled;
                                      }
                                    }
                                    return navigate(
                                      event,
                                      () => searchFocus.requestFocus(),
                                      () => focusChannel(),
                                    );
                                  },
                                  child: TextButton(
                                    focusNode: categoryNode(category.id),
                                    style:
                                        TextButton.styleFrom(
                                          side: const BorderSide(
                                            color: Colors.transparent,
                                          ),
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                              (categoryId ?? '') == category.id
                                              ? const Color(0xff29466a)
                                              : null,
                                          textStyle: const TextStyle(
                                            fontSize: 12,
                                          ),
                                        ).copyWith(
                                          side: WidgetStateProperty.resolveWith(
                                            (states) => BorderSide(
                                              color:
                                                  states.contains(
                                                    WidgetState.focused,
                                                  )
                                                  ? const Color(0xff64b5f6)
                                                  : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                    onPressed: () => setState(() {
                                      categoryId = category.id.isEmpty
                                          ? null
                                          : category.id;
                                      if (vertical.hasClients) {
                                        vertical.jumpTo(0);
                                      }
                                    }),
                                    child: Text(category.name),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          Container(
                            width: 163,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 12),
                            color: const Color(0xff29313c),
                            child: const Text(
                              'CHANNEL',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: horizontal,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: timelineWidth,
                                child: Row(
                                  children: [
                                    for (var i = 0; i < 12; i++)
                                      Container(
                                        width: guideDurationWidth(
                                          const Duration(minutes: 30),
                                        ),
                                        height: 36,
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.only(
                                          left: 10,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: Color(0xff29313c),
                                          border: Border(
                                            left: BorderSide(
                                              color: Color(0xff101419),
                                              width: 2,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          time(
                                            windowStart.add(
                                              Duration(minutes: i * 30),
                                            ),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
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
                    Expanded(
                      child: AsyncView(
                        future: channels,
                        retry: () => setState(() {
                          channels = load();
                        }),
                        builder: (rows) {
                          final visible = rows
                              .where(
                                (item) =>
                                    item.name.toLowerCase().contains(query) &&
                                    (categoryId == null ||
                                        item.categoryId == categoryId),
                              )
                              .toList();
                          displayed = visible;
                          if (initialFocusPending && visible.isNotEmpty) {
                            initialFocusPending = false;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) focusChannel();
                            });
                          }
                          if (visible.isEmpty) {
                            return const Center(
                              child: Text('No channels available'),
                            );
                          }
                          return ListView.builder(
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              0,
                            ),
                            controller: vertical,
                            itemExtent: 52,
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                timelineRow(visible[index], index),
                          );
                        },
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
  );
}

class _ProgrammeCell extends StatefulWidget {
  final EpgProgramme programme;
  final String time;
  final VoidCallback onFocus, onTap;
  const _ProgrammeCell({
    super.key,
    required this.programme,
    required this.time,
    required this.onFocus,
    required this.onTap,
  });
  @override
  State<_ProgrammeCell> createState() => _ProgrammeCellState();
}

class _ProgrammeCellState extends State<_ProgrammeCell> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.programme;
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: focused ? const Color(0xffe8edf3) : const Color(0xff232a32),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) {
              setState(() => focused = value);
              if (value) widget.onFocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: focused ? Colors.black87 : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.time,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: focused ? Colors.black54 : Colors.white54,
                    ),
                  ),
                  if (p.isCurrent(now)) ...[
                    const SizedBox(height: 3),
                    LinearProgressIndicator(
                      value:
                          now.difference(p.start).inMilliseconds /
                          p.end.difference(p.start).inMilliseconds,
                      minHeight: 3,
                      color: const Color(0xff529cff),
                      backgroundColor: Colors.white24,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
