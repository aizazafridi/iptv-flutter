import 'package:flutter/material.dart';
import '../domain/models.dart';

class CatchUpPanel extends StatefulWidget {
  final String channelName;
  final Future<List<EpgProgramme>> Function() load;
  const CatchUpPanel({
    super.key,
    required this.channelName,
    required this.load,
  });
  @override
  State<CatchUpPanel> createState() => _CatchUpPanelState();
}

class _CatchUpPanelState extends State<CatchUpPanel> {
  late Future<List<EpgProgramme>> programmes = widget.load();
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xED151515),
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: 420,
      height: 520,
      child: Column(
        children: [
          ListTile(
            title: const Text('Catch-up', style: TextStyle(fontSize: 18)),
            subtitle: Text(widget.channelName, maxLines: 1),
            trailing: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EpgProgramme>>(
              future: programmes,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        programmes = widget.load();
                      }),
                      child: const Text('Could not load catch-up. Retry'),
                    ),
                  );
                }
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No catch-up programmes are available for this channel.',
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final p = entries[index];
                    final local = p.start.toLocal();
                    final locale = MaterialLocalizations.of(context);
                    String time(DateTime date) => locale.formatTimeOfDay(
                      TimeOfDay.fromDateTime(date.toLocal()),
                      alwaysUse24HourFormat: true,
                    );
                    return ListTile(
                      dense: true,
                      autofocus: index == 0,
                      title: Text(
                        p.title,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        '${locale.formatShortDate(local)}  ${time(p.start)} - ${time(p.end)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.play_arrow, size: 20),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
