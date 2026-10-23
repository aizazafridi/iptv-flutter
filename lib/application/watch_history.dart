import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/models.dart';
import '../domain/iptv_provider.dart';

class WatchEntry {
  final ContentItem item;
  final Episode? episode;
  final Duration position, duration;
  final DateTime updated;
  const WatchEntry(
    this.item,
    this.episode,
    this.position,
    this.duration,
    this.updated,
  );
  String get id => '${item.type.name}:${item.id}:${episode?.id ?? ''}';
  Map<String, dynamic> toJson() => {
    'id': item.id,
    'name': item.name,
    'type': item.type.name,
    'artwork': item.artwork?.toString(),
    'extension': item.extension,
    'categoryId': item.categoryId,
    'position': position.inMilliseconds,
    'duration': duration.inMilliseconds,
    'updated': updated.toIso8601String(),
    if (episode != null)
      'episode': {
        'id': episode!.id,
        'title': episode!.title,
        'season': episode!.season,
        'number': episode!.number,
        'extension': episode!.extension,
      },
  };
  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    final e = json['episode'] as Map<String, dynamic>?;
    return WatchEntry(
      ContentItem(
        id: json['id'],
        name: json['name'],
        type: ContentType.values.byName(json['type']),
        artwork: json['artwork'] == null ? null : Uri.tryParse(json['artwork']),
        extension: json['extension'],
        categoryId: json['categoryId'],
      ),
      e == null
          ? null
          : Episode(
              id: e['id'],
              title: e['title'],
              season: e['season'],
              number: e['number'],
              extension: e['extension'],
            ),
      Duration(milliseconds: json['position']),
      Duration(milliseconds: json['duration']),
      DateTime.parse(json['updated']),
    );
  }
}

/// No playback URLs or passwords are stored. History is isolated per account.
class WatchHistory extends ChangeNotifier {
  static final _providers = Expando<WatchHistory>();
  static String scopeFor(ProviderConfig config) =>
      config.profileId ??
      base64Url.encode(
        utf8.encode(
          jsonEncode([
            config.providerId,
            config.server.replaceFirst(RegExp(r'/+$'), ''),
            config.username,
          ]),
        ),
      );
  static void attach(
    IptvProvider provider,
    ProviderConfig config, {
    WatchHistory? history,
  }) {
    _providers[provider] = history ?? WatchHistory(scopeFor(config));
  }

  static WatchHistory forProvider(IptvProvider provider) =>
      _providers[provider] ??= WatchHistory('fixture-${provider.displayName}');
  final String scope;
  final FlutterSecureStorage storage;
  WatchHistory(this.scope, {this.storage = const FlutterSecureStorage()});
  List<WatchEntry> _entries = [];
  List<WatchEntry> _resumeEntries = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> _load() => _loading ??= () async {
    try {
      final saved = await storage.read(key: 'watch_history:$scope');
      if (saved != null) {
        _entries = (jsonDecode(saved) as List)
            .map((row) => WatchEntry.fromJson(row as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      /* History must never prevent playback. */
    }
    try {
      final saved = await storage.read(key: 'resume_positions:$scope');
      if (saved == null) {
        // Migrate existing positions before history can be cleared.
        _resumeEntries = List.of(_entries);
        await storage.write(
          key: 'resume_positions:$scope',
          value: jsonEncode(
            _resumeEntries.map((entry) => entry.toJson()).toList(),
          ),
        );
      } else {
        _resumeEntries = (jsonDecode(saved) as List)
            .map((row) => WatchEntry.fromJson(row as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _resumeEntries = List.of(_entries);
    }
  }();
  Future<List<WatchEntry>> entries() async {
    await _load();
    return List.unmodifiable(_entries);
  }

  Future<WatchEntry?> latest(ContentItem item, {Episode? episode}) async {
    await _load();
    for (final entry in _resumeEntries) {
      if (entry.item.type == item.type &&
          entry.item.id == item.id &&
          (episode == null || entry.episode?.id == episode.id)) {
        return entry;
      }
    }
    return null;
  }

  Future<List<ContentItem>> items(ContentType type) async {
    final seen = <String>{};
    return [
      for (final entry in await entries())
        if (entry.item.type == type && seen.add(entry.item.id)) entry.item,
    ];
  }

  int _revision = 0;
  Future<void> _queue(Future<void> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.catchError((_) {});
    return result;
  }

  Future<void> clear({ContentType? type}) async {
    await _load();
    final before = _entries;
    final remaining = type == null
        ? <WatchEntry>[]
        : _entries.where((entry) => entry.item.type != type).toList();
    final revision = ++_revision;
    _entries = remaining;
    final value = jsonEncode(remaining.map((entry) => entry.toJson()).toList());
    final write = _queue(() async {
      // Clearing history must never overwrite resume data from another view.
      if (remaining.isEmpty) {
        await storage.delete(key: 'watch_history:$scope');
      } else {
        await storage.write(key: 'watch_history:$scope', value: value);
      }
    });
    notifyListeners();
    try {
      await write;
    } catch (_) {
      if (_revision == revision) {
        _entries = before;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> save(WatchEntry entry) async {
    await _load();
    // Buffering, startup and shutdown can report zero/unknown values. These
    // must not remove a previously valid resume point or Continue Watching row.
    if (entry.position.inSeconds < 1 || entry.duration <= Duration.zero) {
      return;
    }
    _revision++;
    _entries.removeWhere((saved) => saved.id == entry.id);
    _resumeEntries.removeWhere((saved) => saved.id == entry.id);
    if (entry.position.inMilliseconds < entry.duration.inMilliseconds * 0.95) {
      _entries.insert(0, entry);
      _resumeEntries.insert(0, entry);
    }
    if (_entries.length > 200) _entries = _entries.take(200).toList();
    final value = jsonEncode(_entries.map((entry) => entry.toJson()).toList());
    final resume = jsonEncode(
      _resumeEntries.map((entry) => entry.toJson()).toList(),
    );
    final write = _queue(() async {
      await storage.write(key: 'resume_positions:$scope', value: resume);
      await storage.write(key: 'watch_history:$scope', value: value);
    });
    notifyListeners();
    try {
      await write;
    } catch (_) {
      /* Playback continues if storage is unavailable. */
    }
  }
}
