import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../application/watch_history.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';

/// Stores channel metadata only, independently of watch-history clearing.
class LastLiveChannel {
  final String scope;
  final FlutterSecureStorage storage;
  LastLiveChannel(this.scope, {this.storage = const FlutterSecureStorage()});
  factory LastLiveChannel.forProvider(IptvProvider provider) =>
      LastLiveChannel(WatchHistory.forProvider(provider).scope);
  Future<void> save(ContentItem channel) async {
    if (channel.type != ContentType.live) return;
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
