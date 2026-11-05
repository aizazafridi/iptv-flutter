import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/browsing_mode.dart';
import '../application/category_locks.dart';
import '../application/multiview_controller.dart';
import '../application/watch_history.dart';
import '../data/artwork_repository.dart';
import '../data/last_live_channel.dart';
import '../data/playback_preferences.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import '../playback/playback_engine.dart';
import '../playback/media_kit_engine.dart';
import '../playback/multiview_platform.dart';
import 'live_channel_browser.dart';
import 'title_access.dart';
import 'lock_password_dialog.dart';

class MultiViewResult {
  final ContentItem? channel;
  final PlaybackSource source;
  const MultiViewResult(this.channel, this.source);
}

class LiveMultiviewScreen extends StatefulWidget {
  final PlaybackSource initialSource;
  final ContentItem? initialChannel;
  final IptvProvider? provider;
  final Future<List<ContentItem>> Function() loadChannels;
  final Future<PlaybackSource> Function(ContentItem) resolveChannel;
  final PlaybackEngine Function()? engineFactory;
  const LiveMultiviewScreen({
    super.key,
    required this.initialSource,
    required this.loadChannels,
    required this.resolveChannel,
    this.initialChannel,
    this.provider,
    this.engineFactory,
  });
  @override
  State<LiveMultiviewScreen> createState() => _LiveMultiviewScreenState();
}

class _LiveMultiviewScreenState extends State<LiveMultiviewScreen>
    with WidgetsBindingObserver {
  static const blue = Color(0xff64b5f6);
  late final controller = MultiViewController(
    createEngine: widget.engineFactory ?? () => MediaKitEngine(multiview: true),
    resolve: widget.resolveChannel,
    onPlayed: (channel) {
      if (widget.provider != null) {
        unawaited(
          LastLiveChannel.forProvider(
            widget.provider!,
          ).save(channel).catchError((Object _) {}),
        );
      }
    },
    maxStreams: widget.provider is StreamLimitProvider
        ? (widget.provider as StreamLimitProvider).maxConcurrentStreams
        : null,
  );
  bool audioInterrupted = false;
  late final platform = MultiviewPlatform((interrupted) {
    if (!mounted || closing) return;
    audioInterrupted = interrupted;
    final resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(run(() => controller.lifecycle(interrupted || !resumed)));
  });
  final panelFocus = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'Multi View Screen ${i + 1}'),
  );
  final headerFocus = List.generate(
    4,
    (i) => FocusNode(debugLabel: 'Multi View header $i'),
  );
  final toolbarFocus = List.generate(
    5,
    (i) => FocusNode(debugLabel: 'Multi View toolbar $i'),
  );
  final selections = List.generate(4, (_) => LiveChannelBrowserSelection());
  int? swapFrom;
  int preferredAudio = 0;
  bool closing = false,
      overlay = false,
      toolbarVisible = true,
      initialized = false;
  Timer? hideTimer;
  bool get lite => BrowsingModeSettings.instance.lite;
  late final preferences = PlaybackPreferences(
    widget.provider == null
        ? 'multiview-local'
        : '${WatchHistory.forProvider(widget.provider!).scope}:multiview',
  );
  Map<String, dynamic> saved = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BrowsingModeSettings.instance.addListener(repaint);
    controller.addListener(repaint);
    unawaited(platform.initialize());
    unawaited(initialize());
  }

  void repaint() {
    if (mounted) setState(() {});
  }

  Future<void> initialize() async {
    saved = await preferences.load();
    if (!mounted || closing) return;
    final settings = saved['multiview'] is Map
        ? Map<String, dynamic>.from(saved['multiview'])
        : <String, dynamic>{};
    preferredAudio = ((settings['preferredAudio'] as num?)?.toInt() ?? 0).clamp(
      0,
      3,
    );
    controller.names = settings['names'] != false;
    controller.logos = settings['logos'] != false;
    controller.autoHide = settings['autoHide'] == true;
    controller.fit = settings['fit'] == 'Fill' ? 'Fill' : 'Original';
    final count = (settings['layout'] as num?)?.toInt() ?? 2;
    // Screen 1 always owns initial audio; remembered audio is only applied by user.
    await controller.initialize(
      widget.initialSource,
      widget.initialChannel,
      layout: count,
    );
    if (!mounted) return;
    setState(() => initialized = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) panelFocus.first.requestFocus();
    });
    reveal();
  }

  Future<void> save() async {
    saved['multiview'] = {
      'layout': controller.count,
      'names': controller.names,
      'logos': controller.logos,
      'autoHide': controller.autoHide,
      'fit': controller.fit,
      'preferredAudio': preferredAudio,
    };
    try {
      await preferences.save(saved);
    } catch (_) {
      message('Could not save Multi View preferences.');
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      message('Could not apply Multi View action.');
    }
  }

  void reveal() {
    hideTimer?.cancel();
    if (mounted && !toolbarVisible) setState(() => toolbarVisible = true);
    if (!controller.autoHide || overlay || swapFrom != null) return;
    hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted ||
          overlay ||
          swapFrom != null ||
          toolbarFocus.any((f) => f.hasFocus) ||
          headerFocus.any((f) => f.hasFocus)) {
        return;
      }
      setState(() => toolbarVisible = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(platform.release());
      unawaited(run(() => controller.lifecycle(true)));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(platform.acquire());
      if (!audioInterrupted) unawaited(run(() => controller.lifecycle(false)));
    }
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    BrowsingModeSettings.instance.removeListener(repaint);
    platform.dispose();
    controller.removeListener(repaint);
    controller.dispose();
    for (final node in [...panelFocus, ...headerFocus, ...toolbarFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  void focusPanel(int index) {
    controller.selected = index.clamp(0, controller.count - 1);
    panelFocus[controller.selected].requestFocus();
    repaint();
    reveal();
  }

  Future<void> exit() async {
    if (closing) return;
    final panel = controller.chosen.source != null
        ? controller.chosen
        : controller.panels
              .where((p) => p.id == controller.audioId && p.source != null)
              .firstOrNull;
    final result = MultiViewResult(
      panel?.channel ?? widget.initialChannel,
      panel?.source ?? widget.initialSource,
    );
    setState(() => closing = true);
    await controller.shutdown();
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> back() async {
    if (swapFrom != null) {
      setState(() => swapFrom = null);
      focusPanel(controller.selected);
      return;
    }
    if (controller.expandedId != null) {
      await controller.collapse();
      if (mounted) focusPanel(controller.selected);
      return;
    }
    await exit();
  }

  Future<void> selectChannel(int index) async {
    if (overlay || closing || controller.busy) return;
    controller.selected = index;
    overlay = true;
    reveal();
    final panel = controller.panels[index];
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (drawerContext) => Dialog(
        alignment: Alignment.centerLeft,
        insetPadding: EdgeInsets.zero,
        backgroundColor: const Color(0xff121b29),
        shape: const RoundedRectangleBorder(),
        child: SizedBox(
          key: const ValueKey('multiview-channel-drawer'),
          width: MediaQuery.sizeOf(context).width * .35,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Choose Channel',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Select a channel for Screen ${index + 1}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xffaab8c9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close channel list',
                      onPressed: () => Navigator.pop(drawerContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LiveChannelBrowser(
                  embedded: true,
                  load: widget.loadChannels,
                  provider: widget.provider,
                  currentId: panel.channel?.id,
                  categoryId: panel.channel?.categoryId,
                  selection: selections[panel.id],
                  onSelect: (channel) async {
                    final provider = widget.provider;
                    if (provider != null) {
                      if (!await requestTitleAccess(
                            drawerContext,
                            provider,
                            channel,
                          ) ||
                          !drawerContext.mounted) {
                        return false;
                      }
                      final locks = CategoryLocks.forProvider(provider);
                      await locks.load();
                      if (!drawerContext.mounted) return false;
                      final category = Category(
                        channel.categoryId ?? '',
                        '',
                        ContentType.live,
                      );
                      if (locks.isLocked(category)) {
                        final pin = await showDialog<String>(
                          context: drawerContext,
                          builder: (_) => LockPasswordDialog(locks: locks),
                        );
                        if (!drawerContext.mounted ||
                            pin == null ||
                            !locks.unlock(category, pin)) {
                          return false;
                        }
                      }
                    }
                    // Close immediately; native initialization only affects the target.
                    Navigator.pop(drawerContext);
                    unawaited(
                      run(() async {
                        await controller.assign(index, channel);
                        if (index == preferredAudio) {
                          await controller.listenTo(index);
                        }
                      }),
                    );
                    return true;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    overlay = false;
    if (mounted) focusPanel(index);
  }

  Future<void> actions(int index) async {
    if (closing || controller.busy || overlay) return;
    if (swapFrom case final source?) {
      setState(() => swapFrom = null);
      if (source != index) await controller.swap(source, index);
      if (mounted) focusPanel(index);
      return;
    }
    if (controller.panels[index].source == null) {
      await selectChannel(index);
      return;
    }
    overlay = true;
    reveal();
    final action = await showDialog<String>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => SimpleDialog(
        title: Text(
          'Screen ${index + 1}',
          style: const TextStyle(fontSize: 19),
        ),
        alignment: Alignment.centerRight,
        children: [
          for (final label in [
            if (controller.panels[index].error != null) 'Retry',
            'Change Channel',
            'Listen to This Channel',
            'Full Screen',
            'Swap With Another Screen',
            'Remove Channel',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, label),
              child: Text(label, style: const TextStyle(fontSize: 14)),
            ),
        ],
      ),
    );
    overlay = false;
    if (!mounted) return;
    switch (action) {
      case 'Retry':
        await run(() => controller.retry(index));
      case 'Change Channel':
        await selectChannel(index);
      case 'Listen to This Channel':
        await run(() => controller.listenTo(index));
      case 'Full Screen':
        await run(() => controller.expand(index));
      case 'Swap With Another Screen':
        startSwap();
      case 'Remove Channel':
        await run(() => controller.remove(index));
    }
    if (mounted) focusPanel(index);
  }

  void startSwap() {
    setState(() {
      swapFrom = controller.selected;
      toolbarVisible = true;
    });
    focusPanel(controller.selected);
  }

  Future<void> layout(int count) async {
    if (!initialized || controller.busy || controller.expandedId != null) {
      return;
    }
    await run(() => controller.setLayout(count));
    await save();
    if (mounted) focusPanel(controller.selected);
  }

  Future<void> layouts() async {
    if (overlay || closing) return;
    overlay = true;
    reveal();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Layouts'),
        children: [
          for (final count in [2, 3, 4])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, count),
              child: Row(
                children: [
                  Icon(
                    count == 2 ? Icons.view_column_outlined : Icons.grid_view,
                  ),
                  const SizedBox(width: 12),
                  Text('$count Screens'),
                  if (count == controller.count) ...[
                    const Spacer(),
                    const Icon(Icons.check, color: blue),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
    overlay = false;
    if (value != null) {
      await layout(value);
    } else if (mounted) {
      focusPanel(controller.selected);
    }
  }

  Future<void> settings() async {
    if (overlay || closing) return;
    overlay = true;
    reveal();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SimpleDialog(
          title: const Text('Multi View Settings'),
          children: [
            for (final item in [
              (
                'Show channel names',
                controller.names,
                (bool v) => controller.names = v,
              ),
              if (!lite)
                (
                  'Show cached channel logos',
                  controller.logos,
                  (bool v) => controller.logos = v,
                ),
              (
                'Auto-hide toolbar',
                controller.autoHide,
                (bool v) => controller.autoHide = v,
              ),
            ])
              SwitchListTile(
                title: Text(item.$1, style: const TextStyle(fontSize: 14)),
                value: item.$2,
                onChanged: (value) {
                  item.$3(value);
                  update(() {});
                  repaint();
                },
              ),
            ListTile(
              title: const Text(
                'Default layout',
                style: TextStyle(fontSize: 14),
              ),
              trailing: DropdownButton<int>(
                value: controller.count,
                items: [
                  for (final value in [2, 3, 4])
                    DropdownMenuItem(
                      value: value,
                      child: Text('$value Screens'),
                    ),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await controller.setLayout(value);
                    update(() {});
                  }
                },
              ),
            ),
            ListTile(
              title: const Text(
                'Preferred audio screen',
                style: TextStyle(fontSize: 14),
              ),
              trailing: DropdownButton<int>(
                value: preferredAudio,
                items: [
                  for (var value = 0; value < 4; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text('Screen ${value + 1}'),
                    ),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    preferredAudio = value;
                    if (value < controller.count) {
                      await controller.listenTo(value);
                    }
                    update(() {});
                  }
                },
              ),
            ),
            ListTile(
              title: const Text('Video fit', style: TextStyle(fontSize: 14)),
              trailing: DropdownButton<String>(
                value: controller.fit,
                items: [
                  for (final value in ['Original', 'Fill'])
                    DropdownMenuItem(
                      value: value,
                      child: Text(value == 'Original' ? 'Fit' : value),
                    ),
                ],
                onChanged: (value) async {
                  if (value != null) {
                    await controller.setFit(value);
                    update(() {});
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                controller.maxStreams == null
                    ? 'Provider connection limit is unknown. Additional streams may be restricted.'
                    : 'Provider limit: ${controller.maxStreams} simultaneous streams.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Available decoder capacity depends on the device, codec and stream resolution. Use fewer screens if playback fails.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (platform.decoderSummary != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  platform.decoderSummary!,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    overlay = false;
    await save();
    if (mounted) {
      focusPanel(controller.selected);
      reveal();
    }
  }

  KeyEventResult panelKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    reveal();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      unawaited(back());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      unawaited(actions(index));
      return KeyEventResult.handled;
    }
    if (controller.expandedId != null) return KeyEventResult.ignored;
    int? next;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (controller.count == 3) {
        if (index > 0) next = 0;
      } else if (index.isOdd) {
        next = index - 1;
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (controller.count == 3) {
        if (index == 0) next = 1;
      } else if (index.isEven && index + 1 < controller.count) {
        next = index + 1;
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (controller.count == 4 && index >= 2) {
        next = index - 2;
      } else if (controller.count == 3 && index == 2) {
        next = 1;
      } else {
        headerFocus[0].requestFocus();
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (controller.count == 4 && index < 2) {
        next = index + 2;
      } else if (controller.count == 3 && index == 1) {
        next = 2;
      } else {
        toolbarFocus[0].requestFocus();
      }
    } else {
      return KeyEventResult.ignored;
    }
    if (next != null) focusPanel(next);
    return KeyEventResult.handled;
  }

  Widget control(
    String text,
    IconData icon,
    VoidCallback action,
    FocusNode node, {
    bool selected = false,
    bool header = false,
  }) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        focusPanel(controller.selected);
        return KeyEventResult.handled;
      }
      final nodes = header ? headerFocus : toolbarFocus;
      final index = nodes.indexOf(node);
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        nodes[(index +
                    (event.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 1))
                .clamp(0, nodes.length - 1)]
            .requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ListenableBuilder(
      listenable: node,
      builder: (_, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextButton.icon(
          focusNode: node,
          onFocusChange: (_) => reveal(),
          onPressed: closing ? null : action,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: selected
                ? const Color(0xff288df0)
                : const Color(0xff121b29),
            padding: EdgeInsets.symmetric(
              horizontal: header ? 12 : 16,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(lite ? 6 : 28),
              side: BorderSide(
                color: node.hasFocus ? blue : const Color(0xff344354),
                width: node.hasFocus ? 2 : 1,
              ),
            ),
          ),
          icon: Icon(icon, size: 20),
          label: Text(text, style: TextStyle(fontSize: header ? 12 : 13)),
        ),
      ),
    ),
  );
  Widget panel(int index) {
    final panel = controller.panels[index];
    final focus = panelFocus[index];
    return Focus(
      focusNode: focus,
      autofocus: index == 0,
      onFocusChange: (focused) {
        if (focused) {
          controller.selected = index;
          repaint();
          reveal();
        }
      },
      onKeyEvent: (_, event) => panelKey(index, event),
      child: GestureDetector(
        onTap: () {
          focusPanel(index);
          unawaited(actions(index));
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: lite ? 0 : 160),
          key: ValueKey('multiview-panel-$index'),
          decoration: BoxDecoration(
            color: const Color(0xff121b29),
            borderRadius: BorderRadius.circular(lite ? 4 : 14),
            border: Border.all(
              color: focus.hasFocus || swapFrom == index
                  ? blue
                  : const Color(0xff344354),
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(lite ? 2 : 11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                if (panel.surface != null)
                  KeyedSubtree(key: panel.surfaceKey, child: panel.surface!),
                if (panel.source == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_circle_outline,
                          size: 36,
                          color: blue,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add a Channel',
                          style: TextStyle(fontSize: 19),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose a live channel to watch here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xffaab8c9),
                          ),
                        ),
                      ],
                    ),
                  ),
                if ((panel.loading || panel.buffering) && panel.error == null)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          panel.buffering
                              ? 'Buffering...'
                              : 'Connecting to channel...',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                if (panel.error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            panel.error!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              TextButton(
                                onPressed: controller.busy
                                    ? null
                                    : () => run(() => controller.retry(index)),
                                child: const Text('Retry'),
                              ),
                              TextButton(
                                onPressed: () => selectChannel(index),
                                child: const Text('Change Channel'),
                              ),
                              TextButton(
                                onPressed: layouts,
                                child: const Text('Fewer screens'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 5, 4, 12),
                      child: Row(
                        children: [
                          if (!lite &&
                              controller.logos &&
                              panel.channel?.artwork != null)
                            _CachedLogo(
                              url: panel.channel!.artwork!.toString(),
                            ),
                          Expanded(
                            child: Text(
                              controller.names
                                  ? (panel.channel?.name ??
                                        panel.source?.title ??
                                        'Screen ${index + 1}')
                                  : 'Screen ${index + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Audio - Screen ${index + 1}',
                            onPressed: panel.engine == null
                                ? null
                                : () => run(() => controller.listenTo(index)),
                            icon: Icon(
                              controller.audioId == panel.id
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                              size: 20,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Full screen - Screen ${index + 1}',
                            onPressed: panel.source == null
                                ? null
                                : () => run(() => controller.expand(index)),
                            icon: const Icon(Icons.fullscreen, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget grid() {
    if (controller.expandedId case final id?) {
      return panel(controller.panels.indexWhere((p) => p.id == id));
    }
    if (controller.count == 2) {
      return Row(
        children: [
          Expanded(child: panel(0)),
          const SizedBox(width: 10),
          Expanded(child: panel(1)),
        ],
      );
    }
    if (controller.count == 3) {
      return Row(
        children: [
          Expanded(flex: 65, child: panel(0)),
          const SizedBox(width: 10),
          Expanded(
            flex: 35,
            child: Column(
              children: [
                Expanded(child: panel(1)),
                const SizedBox(height: 10),
                Expanded(child: panel(2)),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (final start in [0, 2]) ...[
          if (start > 0) const SizedBox(height: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(child: panel(start)),
                const SizedBox(width: 10),
                Expanded(child: panel(start + 1)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !overlay) unawaited(back());
    },
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!overlay) unawaited(back());
        },
      },
      child: Scaffold(
        backgroundColor: const Color(0xff0d121b),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              children: [
                if (controller.expandedId == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 1000;
                        final title = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compact) ...[
                              const Text(
                                'Streamora',
                                style: TextStyle(
                                  color: blue,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 32),
                            ],
                            const Icon(Icons.grid_view, color: blue, size: 27),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Multi View',
                                  style: TextStyle(
                                    fontSize: compact ? 22 : 28,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Text(
                                  'Watch up to 4 channels at the same time',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xffaab8c9),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                        final controls = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final entry in [4, 2, 3].indexed)
                              control(
                                '${entry.$2} Screens',
                                entry.$2 == 2
                                    ? Icons.view_column_outlined
                                    : Icons.grid_view,
                                () => layout(entry.$2),
                                headerFocus[entry.$1],
                                selected: controller.count == entry.$2,
                                header: true,
                              ),
                            IconButton(
                              focusNode: headerFocus[3],
                              tooltip: 'Multi View Settings',
                              onPressed: settings,
                              icon: const Icon(Icons.settings_outlined),
                            ),
                          ],
                        );
                        if (constraints.maxWidth < 760) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 8),
                              controls,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: title,
                              ),
                            ),
                            controls,
                          ],
                        );
                      },
                    ),
                  ),
                if (controller.warning != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.warning!,
                          style: const TextStyle(
                            color: Color(0xffffd18c),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss warning',
                        onPressed: () {
                          controller.warning = null;
                          repaint();
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                if (swapFrom != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Select the screen to swap with. Back cancels.',
                      style: TextStyle(color: blue, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: closing
                      ? const ColoredBox(color: Colors.black)
                      : grid(),
                ),
                if (controller.expandedId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: TextButton.icon(
                      onPressed: () async {
                        await controller.collapse();
                        if (mounted) focusPanel(controller.selected);
                      },
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Return to Multi View'),
                    ),
                  )
                else if (toolbarVisible)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        children: [
                          control(
                            'Channel List',
                            Icons.playlist_play,
                            () => selectChannel(controller.selected),
                            toolbarFocus[0],
                          ),
                          control(
                            'Swap Screens',
                            Icons.swap_horiz,
                            startSwap,
                            toolbarFocus[1],
                          ),
                          control(
                            'Audio Focus',
                            Icons.volume_up,
                            () => run(
                              () => controller.listenTo(controller.selected),
                            ),
                            toolbarFocus[2],
                          ),
                          control(
                            'Layouts',
                            Icons.grid_view,
                            layouts,
                            toolbarFocus[3],
                          ),
                          const SizedBox(width: 30),
                          control(
                            'Exit Multi View',
                            Icons.close,
                            exit,
                            toolbarFocus[4],
                          ),
                        ],
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
}

/// Logos are optional and disk-only: Multi View never competes with video traffic.
class _CachedLogo extends StatefulWidget {
  final String url;
  const _CachedLogo({required this.url});
  @override
  State<_CachedLogo> createState() => _CachedLogoState();
}

class _CachedLogoState extends State<_CachedLogo> {
  late final file = ArtworkRepository.instance.getFileFromCache(
    ArtworkRepository.cacheKey(widget.url),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: file,
    builder: (context, snapshot) => snapshot.data == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Image.file(
              snapshot.data!.file,
              width: 36,
              height: 24,
              cacheWidth: 72,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
  );
}
