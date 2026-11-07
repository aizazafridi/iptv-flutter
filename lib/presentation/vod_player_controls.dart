import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VodPlayerControls extends StatelessWidget {
  final String title, metadata, positionLabel, durationLabel;
  final double position, duration;
  final int seekSeconds;
  final bool visible, playing, seekEnabled, seeking;
  final FocusNode playFocus, seekFocus;
  final VoidCallback onActivity, onPlay, onRewind, onForward;
  final VoidCallback? onPrevious, onNext, onEpisodes, onAudio;
  final VoidCallback onSubtitles, onMore;
  final ValueChanged<double> onSeekChanged, onSeekEnd;
  const VodPlayerControls({
    super.key,
    this.seekSeconds = 10,
    required this.title,
    required this.metadata,
    required this.positionLabel,
    required this.durationLabel,
    required this.position,
    required this.duration,
    required this.visible,
    required this.playing,
    required this.seekEnabled,
    required this.seeking,
    required this.playFocus,
    required this.seekFocus,
    required this.onActivity,
    required this.onPlay,
    required this.onRewind,
    required this.onForward,
    this.onPrevious,
    this.onNext,
    this.onEpisodes,
    this.onAudio,
    required this.onSubtitles,
    required this.onMore,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });
  static double overlayHeightFor(double viewportHeight) =>
      (viewportHeight * .25).clamp(190.0, 244.0);
  static String displayTitle(String title, String metadata) => title
      .replaceAllMapped(
        RegExp(r'\s*\(((?:19|20)\d{2})\)'),
        (match) => metadata.contains(match[1]!) ? '' : match[0]!,
      )
      .trim();
  double get controlsWidth =>
      42 +
      64 *
          (4 +
              (onPrevious == null ? 0 : 1) +
              (onNext == null ? 0 : 1) +
              (onEpisodes == null ? 0 : 1) +
              (onAudio == null ? 0 : 1));
  Widget action(
    String label,
    IconData icon,
    VoidCallback? callback, {
    bool primary = false,
    FocusNode? node,
  }) => _VodAction(
    key: ValueKey(primary ? 'vod-play-action' : 'vod-$label'),
    label: label,
    icon: icon,
    callback: callback,
    primary: primary,
    focusNode: node,
  );
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeFocus(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Duration(milliseconds: visible ? 170 : 230),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack) {
              return KeyEventResult.ignored;
            }
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              onActivity();
              if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                  !seekFocus.hasFocus) {
                seekFocus.requestFocus();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: Container(
            key: const ValueKey('vod-controls'),
            constraints: BoxConstraints(
              minHeight: overlayHeightFor(MediaQuery.sizeOf(context).height),
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0xb3000000),
                  Color(0xf0000000),
                ],
                stops: [0, .35, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle(title, metadata),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  if (metadata.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        metadata,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 12.5,
                          color: Color(0xffb4becc),
                        ),
                      ),
                    ),
                  if (seeking)
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Seek to $positionLabel \u00b7 OK confirm \u00b7 Back cancel',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ListenableBuilder(
                    listenable: seekFocus,
                    builder: (_, _) => SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        activeTrackColor: const Color(0xff64b5f6),
                        inactiveTrackColor: const Color(0xff454f5d),
                        thumbColor: const Color(0xff64b5f6),
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: seekFocus.hasFocus ? 7 : 0,
                        ),
                      ),
                      child: SizedBox(
                        height: 32,
                        child: Slider(
                          focusNode: seekFocus,
                          min: 0,
                          max: duration > 0 ? duration : 1,
                          value: position.clamp(0, duration > 0 ? duration : 1),
                          onChanged: seekEnabled ? onSeekChanged : null,
                          onChangeEnd: seekEnabled ? onSeekEnd : null,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        positionLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xffb4becc),
                        ),
                      ),
                      Text(
                        durationLabel,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xffb4becc),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < controlsWidth
                            ? controlsWidth
                            : constraints.maxWidth,
                        child: Row(
                          children: [
                            if (onPrevious != null)
                              action(
                                'Previous',
                                Icons.skip_previous_rounded,
                                onPrevious,
                              ),
                            action(
                              'Rewind ${seekSeconds}s',
                              seekSeconds == 10
                                  ? Icons.replay_10_rounded
                                  : seekSeconds == 30
                                  ? Icons.replay_30_rounded
                                  : Icons.replay_rounded,
                              seekEnabled ? onRewind : null,
                            ),
                            action(
                              playing ? 'Pause' : 'Play',
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              onPlay,
                              primary: true,
                              node: playFocus,
                            ),
                            action(
                              'Forward ${seekSeconds}s',
                              seekSeconds == 10
                                  ? Icons.forward_10_rounded
                                  : seekSeconds == 30
                                  ? Icons.forward_30_rounded
                                  : Icons.forward_rounded,
                              seekEnabled ? onForward : null,
                            ),
                            if (onNext != null)
                              action('Next', Icons.skip_next_rounded, onNext),
                            const Spacer(),
                            if (onEpisodes != null)
                              action(
                                'Episodes',
                                Icons.playlist_play,
                                onEpisodes,
                              ),
                            action(
                              'Subtitles',
                              Icons.subtitles_outlined,
                              onSubtitles,
                            ),
                            if (onAudio != null)
                              action(
                                'Audio',
                                Icons.audiotrack_outlined,
                                onAudio,
                              ),
                            action('More', Icons.tune, onMore),
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
      ),
    ),
  );
}

class _VodAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? callback;
  final bool primary;
  final FocusNode? focusNode;
  const _VodAction({
    super.key,
    required this.label,
    required this.icon,
    required this.callback,
    required this.primary,
    this.focusNode,
  });
  @override
  State<_VodAction> createState() => _VodActionState();
}

class _VodActionState extends State<_VodAction> {
  late final node =
      widget.focusNode ?? FocusNode(debugLabel: 'player ${widget.label}');
  @override
  void dispose() {
    if (widget.focusNode == null) node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.callback != null;
    final focused = node.hasFocus;
    return SizedBox(
      width: widget.primary ? 42 : 64,
      height: 62,
      child: Semantics(
        label: widget.label,
        button: true,
        enabled: enabled,
        excludeSemantics: true,
        child: Focus(
          focusNode: node,
          canRequestFocus: enabled,
          onFocusChange: (value) {
            setState(() {});
            if (value) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 150),
              );
            }
          },
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                [
                  LogicalKeyboardKey.enter,
                  LogicalKeyboardKey.select,
                  LogicalKeyboardKey.space,
                ].contains(event.logicalKey)) {
              widget.callback?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: InkWell(
            canRequestFocus: false,
            onTap: widget.callback,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  key: widget.primary ? const ValueKey('vod-play-pause') : null,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: widget.primary ? 42 : 60,
                  height: widget.primary ? 42 : 34,
                  decoration: BoxDecoration(
                    color: focused
                        ? const Color(0xfff0f4f8)
                        : widget.primary
                        ? Colors.white24
                        : Colors.transparent,
                    shape: widget.primary
                        ? BoxShape.circle
                        : BoxShape.rectangle,
                    borderRadius: widget.primary
                        ? null
                        : BorderRadius.circular(10),
                    border: Border.all(
                      color: focused
                          ? const Color(0xff64b5f6)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.primary ? 24 : 20,
                    color: !enabled
                        ? Colors.white30
                        : focused
                        ? const Color(0xff111820)
                        : Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedOpacity(
                  opacity: focused ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    widget.label.startsWith('Rewind ')
                        ? 'Rewind'
                        : widget.label.startsWith('Forward ')
                        ? 'Forward'
                        : widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 11.5,
                      height: 1.0,
                      color: Colors.white,
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
}
