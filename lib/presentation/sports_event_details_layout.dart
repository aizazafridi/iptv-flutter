import 'package:flutter/material.dart';
import '../domain/sports.dart';
import 'sports_match_graphics.dart';

class SportsEventDetailsLayout extends StatefulWidget {
  final SportsEvent event;
  final bool lite;
  final String status, date, attribution;
  final Widget actions, channels;
  const SportsEventDetailsLayout({
    super.key,
    required this.event,
    required this.lite,
    required this.status,
    required this.date,
    required this.attribution,
    required this.actions,
    required this.channels,
  });
  @override
  State<SportsEventDetailsLayout> createState() => _DetailsState();
}

class _DetailsState extends State<SportsEventDetailsLayout> {
  int tab = 0;
  SportsEvent get event => widget.event;
  bool get cricket => event.sportId == 'Cricket';
  Widget panel(String title, IconData icon, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xf0142d46), Color(0xf00b192b)],
      ),
      border: Border.all(color: const Color(0xff304d69)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xff64b5f6), size: 23),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ...children,
      ],
    ),
  );
  Widget field(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value ?? 'Not supplied',
            style: const TextStyle(fontSize: 14, color: Color(0xffc6d2df)),
          ),
        ),
      ],
    ),
  );
  Widget get information => panel('Match Information', Icons.info_outline, [
    field('Date', widget.date),
    field('Venue', event.venue),
    field(cricket ? 'Series' : 'Competition', event.leagueName),
    if (event.season != null) field('Season', event.season),
    if (event.round != null) field('Round', event.round),
    field('Status', widget.status),
    if (event.scoreUpdate?.detail != null || event.scoreDetail != null)
      field('Summary', event.scoreUpdate?.detail ?? event.scoreDetail),
  ]);
  Widget get progress =>
      panel(cricket ? 'Match Progress' : 'Match Summary', Icons.bar_chart, [
        SportsScoreboard(event: event, lite: widget.lite),
        const SizedBox(height: 12),
        if (!cricket && event.displayScore != null)
          Text(
            event.displayScore!,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        if (event.scoreUpdate?.period != null)
          field('Period', event.scoreUpdate!.period),
        if (event.scoreUpdate?.clock != null)
          field('Clock', event.scoreUpdate!.clock),
        if (event.scoreUpdate != null)
          Text(
            event.scoreUpdate!.label,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        if (event.scoreUpdate?.updatedAt != null)
          Text(
            'Score updated: ${event.scoreUpdate!.updatedAt!.toLocal()}',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
      ]);
  Widget get statistics => panel(
    cricket ? 'Detailed Scorecard' : 'Match Statistics',
    Icons.analytics_outlined,
    [
      Text(
        cricket
            ? 'Batting and bowling statistics are not supplied by the current data provider.'
            : 'Possession, shots and other match statistics are not supplied by the current data provider.',
        style: const TextStyle(fontSize: 14, color: Color(0xffb8c7d9)),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final sport = event.sportId == 'Soccer'
        ? 'Football'
        : event.sportId ?? 'Sport';
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xff081a30),
            image: widget.lite
                ? null
                : const DecorationImage(
                    image: AssetImage('assets/sports/stadium_header.jpg'),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: widget.lite
                  ? null
                  : const LinearGradient(
                      colors: [
                        Color(0xee07152a),
                        Color(0xbb07152a),
                        Color(0x8807152a),
                      ],
                    ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      sportsIcon(event.sportId),
                      color: const Color(0xff64b5f6),
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$sport | ${event.leagueName ?? 'Competition'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xff64b5f6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  event.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: event.scoreIsLive
                        ? const Color(0xffd7192b)
                        : const Color(0xff30465e),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    event.scoreIsLive ? 'LIVE' : widget.status,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (event.homeTeamName != null || event.awayTeamName != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xcc041427),
                      border: Border.all(color: const Color(0xff355d83)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SportsScoreboard(event: event, lite: widget.lite),
                  ),
                if (event.scoreUpdate?.detail != null ||
                    event.scoreDetail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      event.scoreUpdate?.detail ?? event.scoreDetail!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xffd4dfed),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                widget.actions,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final entry in [
                'Overview',
                cricket ? 'Scorecard' : 'Stats',
              ].indexed)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: tab == entry.$1,
                  selectedColor: const Color(0xff126bd4),
                  onSelected: (_) => setState(() => tab = entry.$1),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final right = Column(
                children: [
                  progress,
                  const SizedBox(height: 14),
                  if (tab == 1 || !cricket) statistics,
                  const SizedBox(height: 14),
                  panel('Available Channels', Icons.live_tv, [widget.channels]),
                ],
              );
              if (constraints.maxWidth < 800) {
                return Column(
                  children: [information, const SizedBox(height: 14), right],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: information),
                  const SizedBox(width: 16),
                  Expanded(child: right),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Text(
            widget.attribution,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}
