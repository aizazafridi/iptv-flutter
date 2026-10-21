import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

class VideoRecording {
  final String id, title;
  final ContentItem item;
  final DateTime created;
  final int durationMs, bytes;
  const VideoRecording({
    required this.id,
    required this.title,
    required this.item,
    required this.created,
    required this.durationMs,
    required this.bytes,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'created': created.toIso8601String(),
    'duration': durationMs,
    'bytes': bytes,
    'itemId': item.id,
    'name': item.name,
    'type': item.type.name,
    'categoryId': item.categoryId,
    'artwork': item.artwork?.toString(),
  };
  factory VideoRecording.fromJson(Map<String, dynamic> data) => VideoRecording(
    id: data['id'],
    title: data['title'],
    created: DateTime.parse(data['created']),
    durationMs: data['duration'],
    bytes: data['bytes'],
    item: ContentItem(
      id: data['itemId'],
      name: data['name'],
      type: ContentType.values.byName(data['type']),
      categoryId: data['categoryId'],
      artwork: Uri.tryParse(data['artwork'] ?? ''),
    ),
  );
}

/// Media and metadata stay in a separate private directory for each profile.
class VideoRecordings extends ChangeNotifier {
  static final Map<String, VideoRecordings> _instances = {};
  static VideoRecordings forScope(String scope) =>
      _instances.putIfAbsent(scope, () => VideoRecordings(scope));
  @visibleForTesting
  static void attach(String scope, VideoRecordings store) =>
      _instances[scope] = store;
  final String scope;
  final Directory? rootOverride;
  VideoRecordings(this.scope, {this.rootOverride});
  List<VideoRecording> entries = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  final Set<String> active = {};
  Future<Directory> directory() async {
    final root = rootOverride ?? await getApplicationSupportDirectory();
    final encoded = base64Url.encode(utf8.encode(scope)).replaceAll('=', '');
    return Directory(
      '${root.path}${Platform.pathSeparator}recordings${Platform.pathSeparator}$encoded',
    ).create(recursive: true);
  }

  Future<File> file(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid recording ID');
    }
    return File('${(await directory()).path}${Platform.pathSeparator}$id.mkv');
  }

  Future<void> load() => _loading ??= () async {
    final index = File(
      '${(await directory()).path}${Platform.pathSeparator}index.json',
    );
    if (await index.exists()) {
      entries = (jsonDecode(await index.readAsString()) as List)
          .map((row) => VideoRecording.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    }
  }();
  Future<T> _queue<T>(Future<T> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _save(List<VideoRecording> rows) async {
    final dir = await directory();
    final index = File('${dir.path}${Platform.pathSeparator}index.json');
    final temp = File('${index.path}.tmp');
    await temp.writeAsString(
      jsonEncode(rows.map((row) => row.toJson()).toList()),
      flush: true,
    );
    await temp.rename(index.path);
    entries = rows;
    notifyListeners();
  }

  Future<String> reserve() async {
    await load();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
    active.add(id);
    return id;
  }

  Future<void> finish(
    String id,
    ContentItem item,
    String title,
    Duration duration,
  ) => _queue(() async {
    await load();
    final media = await file(id);
    final bytes = await media.exists() ? await media.length() : 0;
    if (bytes < 1024) {
      throw const FileSystemException(
        'The stream did not produce a playable recording.',
      );
    }
    await _save([
      VideoRecording(
        id: id,
        title: title,
        item: item,
        created: DateTime.now(),
        durationMs: duration.inMilliseconds,
        bytes: bytes,
      ),
      ...entries,
    ]);
    active.remove(id);
  });
  Future<void> discard(String id) => _queue(() async {
    final media = await file(id);
    if (await media.exists()) await media.delete();
    active.remove(id);
  });
  Future<void> delete(VideoRecording entry) => _queue(() async {
    await load();
    final media = await file(entry.id);
    if (await media.exists()) await media.delete();
    await _save(entries.where((row) => row.id != entry.id).toList());
  });
  Future<void> deleteAll() => _queue(() async {
    await load();
    if (active.isNotEmpty) {
      throw StateError('Stop recording before deleting all recordings.');
    }
    final remaining = List<VideoRecording>.of(entries);
    for (final row in List<VideoRecording>.of(entries)) {
      final media = await file(row.id);
      if (await media.exists()) await media.delete();
      remaining.remove(row);
      await _save(List.of(remaining));
    }
  });
}
