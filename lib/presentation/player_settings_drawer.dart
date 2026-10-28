import 'package:flutter/material.dart';
import '../playback/video_display.dart';

class PlayerSettingsDrawer extends StatefulWidget {
  final bool? autoplay;
  final double rate;
  final int seekSeconds;
  final String? ratio;
  final bool allowSpeed;
  final Future<void> Function(bool) onAutoplay;
  final Future<void> Function(double) onRate;
  final Future<void> Function(int) onSeek;
  final Future<void> Function(String) onRatio;
  const PlayerSettingsDrawer({
    super.key,
    required this.autoplay,
    required this.rate,
    required this.seekSeconds,
    required this.ratio,
    required this.allowSpeed,
    required this.onAutoplay,
    required this.onRate,
    required this.onSeek,
    required this.onRatio,
  });
  @override
  State<PlayerSettingsDrawer> createState() => _PlayerSettingsDrawerState();
}

class _PlayerSettingsDrawerState extends State<PlayerSettingsDrawer> {
  late bool autoplay = widget.autoplay ?? false;
  late double rate = widget.rate;
  late int seek = widget.seekSeconds;
  late String? ratio = widget.ratio;
  bool busy = false;
  String? error;
  Future<void> apply(
    Future<void> Function() action,
    VoidCallback commit,
  ) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) setState(commit);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not apply setting. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget row(
    String id,
    String title,
    String value,
    List<Widget> choices, {
    bool first = false,
  }) {
    final heading = Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (id != 'autoplay')
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Color(0xffadb9c8)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey('settings-card-$id'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xff27313e),
          borderRadius: BorderRadius.circular(14),
        ),
        child: id == 'autoplay'
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xffadb9c8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    toggled: autoplay,
                    child: option(
                      value,
                      false,
                      () => apply(
                        () => widget.onAutoplay(!autoplay),
                        () => autoplay = !autoplay,
                      ),
                      autofocus: true,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final choice in choices)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: choice,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget option(
    String label,
    bool selected,
    VoidCallback action, {
    bool autofocus = false,
    bool light = false,
  }) => OutlinedButton(
    autofocus: autofocus,
    onPressed: busy ? null : action,
    style: ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const WidgetStatePropertyAll(Size(48, 34)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const Color(0xff34465f)
            : selected
            ? (light ? const Color(0xffeeeeee) : const Color(0xff202020))
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => selected && light && !states.contains(WidgetState.focused)
            ? Colors.black
            : const Color(0xffc0c5cd),
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          width: states.contains(WidgetState.focused) ? 2 : 1,
          color: states.contains(WidgetState.focused)
              ? const Color(0xff64b5f6)
              : light || autofocus
              ? Colors.white24
              : Colors.transparent,
        ),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      if (widget.autoplay != null)
        row(
          'autoplay',
          'Autoplay Next Episode',
          autoplay ? 'On' : 'Off',
          [],
          first: true,
        ),
      if (widget.allowSpeed)
        row('speed', 'Playback Speed', '$rate\u00d7', [
          for (final value in [0.5, 1.0, 1.5, 0.75, 1.25, 2.0, 3.0, 5.0])
            option(
              '$value\u00d7',
              rate == value,
              () => apply(() => widget.onRate(value), () => rate = value),
            ),
        ], first: widget.autoplay == null),
      row('seek', 'Seek Interval', '$seek seconds', [
        for (final value in [10, 20, 30, 60, 120, 180])
          option(
            '${value}s',
            seek == value,
            () => apply(() => widget.onSeek(value), () => seek = value),
            light: true,
          ),
      ]),
      if (ratio != null)
        row('aspect', 'Aspect Ratio', ratio == 'Original' ? 'Fit' : ratio!, [
          for (final value in [
            'Original',
            'Fill',
            'Stretch',
            ...VideoDisplay.ratios.where(
              (r) => !['Original', 'Fill', 'Stretch'].contains(r),
            ),
          ])
            option(
              value == 'Original' ? 'Fit' : value,
              ratio == value,
              () => apply(() => widget.onRatio(value), () => ratio = value),
            ),
        ]),
      if (error != null)
        Text(
          error!,
          style: const TextStyle(color: Color(0xffffb4ab), fontSize: 12),
        ),
    ],
  );
}
