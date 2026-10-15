import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RecordedSegment {
  final Duration start, end;
  const RecordedSegment(this.start, this.end);
  String get label => '${format(start)} – ${format(end)}';
  static String format(Duration time) {
    final seconds = time.inSeconds;
    final minutes = (seconds ~/ 60).remainder(60).toString().padLeft(2, '0');
    final remaining = seconds.remainder(60).toString().padLeft(2, '0');
    return '${seconds ~/ 3600}:$minutes:$remaining';
  }
}

/// Stores only playback positions, isolated by account, title and episode.
/// No video, authenticated playback URL, or downloaded media is stored.
class RecordedSegments extends ChangeNotifier {
  final String scope, mediaId;
  final FlutterSecureStorage storage;
  RecordedSegments(
    this.scope,
    this.mediaId, {
    this.storage = const FlutterSecureStorage(),
  });
  bool _closed = false;
  @override
  void notifyListeners() {
    if (!_closed) super.notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  List<RecordedSegment> entries = [];
  bool loaded = false, saving = false;
  Duration? recordingStart;
  RecordedSegment? activeLoop;
  String get key =>
      'recorded_segments:${base64Url.encode(utf8.encode(jsonEncode([scope, mediaId])))}';
  Future<void> load() async {
    final saved = await storage.read(key: key);
    if (saved != null) {
      final rows = jsonDecode(saved) as List;
      entries = rows
          .whereType<Map>()
          .where(
            (row) =>
                row['start'] is int &&
                row['end'] is int &&
                row['start'] >= 0 &&
                row['end'] > row['start'],
          )
          .map(
            (row) => RecordedSegment(
              Duration(milliseconds: row['start']),
              Duration(milliseconds: row['end']),
            ),
          )
          .toList();
    }
    loaded = true;
    notifyListeners();
  }

  void begin(Duration position) {
    activeLoop = null;
    recordingStart = position;
    notifyListeners();
  }

  Future<void> finish(Duration position) async {
    final start = recordingStart;
    if (start == null || saving) return;
    if (position <= start) throw StateError('End must follow start');
    saving = true;
    notifyListeners();
    try {
      final saved = [...entries, RecordedSegment(start, position)];
      await storage.write(
        key: key,
        value: jsonEncode(
          saved
              .map(
                (s) => {
                  'start': s.start.inMilliseconds,
                  'end': s.end.inMilliseconds,
                },
              )
              .toList(),
        ),
      );
      entries = saved;
      recordingStart = null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  /// Passing null deletes all ranges for this media selection only.
  Future<void> delete(RecordedSegment? segment) async {
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      final remaining = segment == null
          ? <RecordedSegment>[]
          : entries.where((entry) => !identical(entry, segment)).toList();
      await storage.write(
        key: key,
        value: jsonEncode(
          remaining
              .map(
                (s) => {
                  'start': s.start.inMilliseconds,
                  'end': s.end.inMilliseconds,
                },
              )
              .toList(),
        ),
      );
      entries = remaining;
      if (segment == null || identical(activeLoop, segment)) activeLoop = null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  void loop(RecordedSegment? segment) {
    activeLoop = segment;
    notifyListeners();
  }
}
