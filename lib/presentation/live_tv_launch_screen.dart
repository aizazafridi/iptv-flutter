import '../playback/playback_engine.dart';
import 'package:flutter/material.dart';
import '../application/live_tv_start.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'player_screen.dart';
import 'widgets.dart';

class LiveTvLaunchScreen extends StatefulWidget {
  final PlaybackEngine Function()? engineFactory;
  final bool openGuide;
  final IptvProvider provider;
  const LiveTvLaunchScreen({
    super.key,
    required this.provider,
    this.openGuide = false,
    this.engineFactory,
  });
  @override
  State<LiveTvLaunchScreen> createState() => _LiveTvLaunchScreenState();
}

class _LiveTvLaunchScreenState extends State<LiveTvLaunchScreen> {
  late Future<LiveTvStart> start = prepareLiveTv(widget.provider);
  Future<List<ContentItem>>? catalogue;
  Future<List<ContentItem>> channels() =>
      catalogue ??= widget.provider.getAllItems(ContentType.live);
  @override
  Widget build(BuildContext context) => FutureBuilder<LiveTvStart>(
    future: start,
    builder: (context, snapshot) {
      final result = snapshot.data;
      if (result != null) {
        final provider = widget.provider;
        return PlayerScreen(
          source: result.source,
          engineFactory: widget.engineFactory,
          item: result.channel,
          provider: provider,
          liveTvMode: true,
          initialChannelPicker: result.firstUse && !widget.openGuide,
          initialGuide: widget.openGuide,
          channelCategory: 'Live TV',
          loadChannels: channels,
          resolveChannel: provider.resolvePlayback,
          channelEpg: provider is EpgProvider
              ? (provider as EpgProvider).getEpg
              : null,
        );
      }
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: const Text('Live TV')),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(safeMessage(snapshot.error!)),
                    TextButton(
                      onPressed: () => setState(() {
                        start = prepareLiveTv(widget.provider);
                      }),
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
