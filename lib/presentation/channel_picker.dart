import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'widgets.dart';

class ChannelPicker extends StatefulWidget {
  final String title;
  final String? currentId;
  final Future<List<ContentItem>> Function() load;
  const ChannelPicker({
    super.key,
    required this.title,
    required this.load,
    this.currentId,
  });
  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<ChannelPicker> {
  late Future<List<ContentItem>> channels = widget.load();
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    alignment: Alignment.centerRight,
    insetPadding: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
    child: Container(
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: ThemeData.dark(),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 20),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Close channels',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: AsyncView(
                future: channels,
                retry: () => setState(() => channels = widget.load()),
                builder: (rows) => rows.isEmpty
                    ? const Center(child: Text('No channels available'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, index) {
                          final channel = rows[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              selected: channel.id == widget.currentId,
                              selectedTileColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              leading: SizedBox(
                                width: 44,
                                height: 44,
                                child: Artwork(channel.artwork),
                              ),
                              title: Text(channel.name),
                              trailing: channel.id == widget.currentId
                                  ? const Icon(Icons.play_arrow)
                                  : null,
                              onTap: () => Navigator.pop(context, channel),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
