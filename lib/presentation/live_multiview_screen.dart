import '../data/last_live_channel.dart';
import 'channel_list_icon.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';
import '../playback/playback_engine.dart';
import '../playback/media_kit_engine.dart';
import '../playback/video_display.dart';
import '../playback/live_stream_recovery.dart';
import '../application/category_locks.dart';
import 'channel_picker.dart';
import 'title_access.dart';
import 'lock_password_dialog.dart';

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

class _LiveMultiviewScreenState extends State<LiveMultiviewScreen> {
  final panes = [GlobalKey<_LivePaneState>(), GlobalKey<_LivePaneState>()];
  int audio = 0, lastAudible = 0;
  bool closing = false, routingAudio = false;
  Future<void> chooseAudio(int index) async {
    if (closing || routingAudio) return;
    routingAudio = true;
    try {
      await Future.wait(
        panes.map(
          (key) => key.currentState?.setVolume(0) ?? Future<void>.value(),
        ),
      );
      if (index >= 0) await panes[index].currentState?.setVolume(100);
      if (mounted) {
        setState(() {
          audio = index;
          if (index >= 0) lastAudible = index;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not switch channel audio.')),
        );
      }
    } finally {
      routingAudio = false;
    }
  }

  Future<void> leave() async {
    if (closing) return;
    for (final pane in panes.reversed) {
      if (pane.currentState?.dismissPicker() ?? false) return;
    }
    setState(() => closing = true);
    await Future.wait(
      panes.map((key) => key.currentState?.close() ?? Future<void>.value()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(leave());
    },
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        leading: BackButton(onPressed: closing ? null : leave),
        toolbarHeight: 48,
        actions: [
          IconButton(
            tooltip: audio < 0 ? 'Unmute audio' : 'Mute both screens',
            icon: Icon(
              audio < 0 ? Icons.volume_off : Icons.volume_up,
              color: Colors.white,
            ),
            onPressed: closing || routingAudio
                ? null
                : () => chooseAudio(audio < 0 ? lastAudible : -1),
          ),
        ],
        title: const Text(
          'Live TV - Split screen',
          style: TextStyle(fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Row(
          children: [
            for (var index = 0; index < 2; index++) ...[
              if (index > 0)
                const VerticalDivider(width: 2, color: Colors.white24),
              Expanded(
                child: _LivePane(
                  key: panes[index],
                  number: index + 1,
                  initialSource: index == 0 ? widget.initialSource : null,
                  initialChannel: index == 0 ? widget.initialChannel : null,
                  provider: widget.provider,
                  loadChannels: widget.loadChannels,
                  resolveChannel: widget.resolveChannel,
                  engineFactory: widget.engineFactory,
                  audible: audio == index,
                  onAudio: () => chooseAudio(index),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LivePane extends StatefulWidget {
  final int number;
  final PlaybackSource? initialSource;
  final ContentItem? initialChannel;
  final IptvProvider? provider;
  final Future<List<ContentItem>> Function() loadChannels;
  final Future<PlaybackSource> Function(ContentItem) resolveChannel;
  final PlaybackEngine Function()? engineFactory;
  final bool audible;
  final VoidCallback onAudio;
  const _LivePane({
    super.key,
    required this.number,
    required this.loadChannels,
    required this.resolveChannel,
    required this.audible,
    required this.onAudio,
    this.initialSource,
    this.initialChannel,
    this.provider,
    this.engineFactory,
  });
  @override
  State<_LivePane> createState() => _LivePaneState();
}

class _LivePaneState extends State<_LivePane> {
  late final engine = widget.engineFactory?.call() ?? MediaKitEngine();
  late final surface = engine.surface();
  late PlaybackSource? source = widget.initialSource;
  late ContentItem? channel = widget.initialChannel;
  final subscriptions = <StreamSubscription<dynamic>>[];
  LiveStreamRecovery? recovery;
  Future<void>? _closing;
  bool loading = false,
      reconnecting = false,
      buffering = false,
      stopping = false;
  Future<void> setVolume(double volume) async {
    if (engine is AudioPlaybackEngine) {
      await (engine as AudioPlaybackEngine).setVolume(volume);
    }
  }

  @override
  void initState() {
    super.initState();
    if (engine is VideoDisplayEngine) {
      (engine as VideoDisplayEngine).setVideoDisplay(
        const VideoDisplay(ratio: 'Original'),
      );
    }
    subscriptions.add(
      engine.position.listen((position) {
        recovery?.progress(position);
      }),
    );
    subscriptions.add(
      engine.playing.listen((playing) {
        if (playing) {
          if (widget.provider != null && channel != null) {
            unawaited(
              LastLiveChannel.forProvider(
                widget.provider!,
              ).save(channel!).catchError((Object _) {}),
            );
          }
          if (mounted) setState(() => loading = false);
        } else if (!loading) {
          recovery?.failed();
        }
      }),
    );
    subscriptions.add(engine.errors.listen((_) => recovery?.failed()));
    if (engine is CompletionPlaybackEngine) {
      subscriptions.add(
        (engine as CompletionPlaybackEngine).completed.listen((done) {
          if (done) recovery?.failed();
        }),
      );
    }
    if (engine is BufferingPlaybackEngine) {
      subscriptions.add(
        (engine as BufferingPlaybackEngine).buffering.listen((value) {
          if (mounted) setState(() => buffering = value);
        }),
      );
    }
    if (source != null) unawaited(open(source!));
  }

  Future<void> open(PlaybackSource next) async {
    await recovery?.close();
    if (!mounted || _closing != null) return;
    setState(() {
      source = next;
      loading = true;
      reconnecting = false;
    });
    recovery = LiveStreamRecovery(
      reconnect: () => engine.open(next),
      onRecovering: (value) {
        if (mounted) setState(() => reconnecting = value);
      },
    );
    try {
      await setVolume(widget.audible ? 100 : 0);
      await engine.open(next);
    } catch (_) {
      recovery?.failed();
      if (mounted) setState(() => loading = false);
    }
  }

  bool picking = false;
  bool dismissPicker() {
    if (!picking) return false;
    setState(() => picking = false);
    return true;
  }

  Future<void> chooseChannel() async {
    setState(() => picking = true);
  }

  Future<void> applyChannel(ContentItem selected) async {
    if (!mounted || _closing != null) return;
    final provider = widget.provider;
    if (provider != null) {
      if (!await requestTitleAccess(context, provider, selected) || !mounted) {
        return;
      }
      if (selected.categoryId != null) {
        final locks = CategoryLocks.forProvider(provider);
        await locks.load();
        if (!mounted) return;
        final category = Category(selected.categoryId!, '', ContentType.live);
        if (locks.isLocked(category)) {
          final pin = await showDialog<String>(
            context: context,
            builder: (_) => LockPasswordDialog(locks: locks),
          );
          if (!mounted || pin == null || !locks.unlock(category, pin)) return;
        }
      }
    }
    try {
      final next = await widget.resolveChannel(selected);
      if (!mounted || _closing != null) return;
      setState(() {
        channel = selected;
        picking = false;
      });
      await open(next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this channel. Check availability and simultaneous-stream limits.',
            ),
          ),
        );
      }
    }
  }

  Future<void> close({bool repaint = true}) {
    if (_closing != null) return _closing!;
    if (repaint && mounted) setState(() => stopping = true);
    return _closing = () async {
      if (repaint && mounted) await WidgetsBinding.instance.endOfFrame;
      await recovery?.close();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
      await engine.dispose();
    }();
  }

  @override
  void dispose() {
    unawaited(close(repaint: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => stopping
      ? const ColoredBox(color: Colors.black)
      : Stack(
          fit: StackFit.expand,
          children: [
            if (source != null) surface,
            if (source == null)
              Center(
                child: TextButton.icon(
                  onPressed: chooseChannel,
                  icon: const Icon(Icons.add),
                  label: Text('Choose channel for screen ${widget.number}'),
                ),
              ),
            if (loading || reconnecting || buffering)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 10),
                    Text(
                      reconnecting
                          ? 'Reconnecting channel...'
                          : 'Loading channel...',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        source?.title ?? 'Screen ${widget.number}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Channels - Screen ${widget.number}',
                      onPressed: chooseChannel,
                      color: Colors.white,
                      icon: const ChannelListIcon(size: 20),
                    ),
                    IconButton(
                      tooltip: 'Audio - Screen ${widget.number}',
                      onPressed: source == null ? null : widget.onAudio,
                      icon: Icon(
                        widget.audible ? Icons.volume_up : Icons.volume_off,
                        color: widget.audible ? Colors.white : Colors.white54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (picking)
              Positioned.fill(
                child: Material(
                  color: Colors.black87,
                  child: ChannelPicker(
                    embedded: true,
                    categoriesFirst: true,
                    title: 'Choose channel - Screen ${widget.number}',
                    currentId: channel?.id,
                    categoryId: channel?.categoryId,
                    provider: widget.provider,
                    load: widget.loadChannels,
                    onClose: dismissPicker,
                    onSelect: (selected) async {
                      await applyChannel(selected);
                      return !picking;
                    },
                  ),
                ),
              ),
          ],
        );
}
