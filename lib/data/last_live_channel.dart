import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../application/watch_history.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';

/// Stores channel metadata only, independently of watch-history clearing.
class LastLiveChannel {
  static final _changes = <String, ValueNotifier<int>>{};
  static final _writes = <String, Future<void>>{};
  Listenable get changes =>
      _changes.putIfAbsent(scope, () => ValueNotifier<int>(0));
  final String scope;
  final FlutterSecureStorage storage;
  LastLiveChannel(this.scope, {this.storage = const FlutterSecureStorage()});
  factory LastLiveChannel.forProvider(IptvProvider provider) =>
      LastLiveChannel(WatchHistory.forProvider(provider).scope);
  Future<void> save(ContentItem channel) {
    final result = (_writes[scope] ?? Future<void>.value()).then(
      (_) => _save(channel),
    );
    _writes[scope] = result.catchError((_) {});
    return result;
  }

  Future<void> _save(ContentItem channel) async {
    if (channel.type != ContentType.live) return;
    final recent = await recentChannels();
    recent.removeWhere((item) => item.id == channel.id);
    recent.insert(0, channel);
    await storage.write(
      key: 'recent_live_channels:$scope',
      value: jsonEncode(
        recent
            .take(5)
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'categoryId': item.categoryId,
                'artwork': item.artwork?.toString(),
                'extension': item.extension,
              },
            )
            .toList(),
      ),
    );
    await storage.write(
      key: 'last_live_channel:$scope',
      value: jsonEncode({
        'id': channel.id,
        'name': channel.name,
        'categoryId': channel.categoryId,
        'artwork': channel.artwork?.toString(),
        'extension': channel.extension,
      }),
    );
    final notifier = _changes.putIfAbsent(scope, () => ValueNotifier<int>(0));
    notifier.value++;
  }

  Future<List<ContentItem>> recentChannels() async {
    final saved = await storage.read(key: 'recent_live_channels:$scope');
    if (saved != null) {
      try {
        return (jsonDecode(saved) as List)
            .map(
              (row) => ContentItem(
                id: row['id'] as String,
                name: row['name'] as String,
                type: ContentType.live,
                categoryId: row['categoryId'] as String?,
                extension: row['extension'] as String?,
                artwork: row['artwork'] == null
                    ? null
                    : Uri.tryParse(row['artwork'] as String),
              ),
            )
            .take(5)
            .toList();
      } catch (_) {
        /* Fall back to the previously saved channel. */
      }
    }
    final last = await load();
    return [?last];
  }

  Future<ContentItem?> load() async {
    final saved = await storage.read(key: 'last_live_channel:$scope');
    if (saved == null) return null;
    try {
      final row = jsonDecode(saved) as Map<String, dynamic>;
      return ContentItem(
        id: row['id'] as String,
        name: row['name'] as String,
        type: ContentType.live,
        categoryId: row['categoryId'] as String?,
        extension: row['extension'] as String?,
        artwork: row['artwork'] == null
            ? null
            : Uri.tryParse(row['artwork'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
