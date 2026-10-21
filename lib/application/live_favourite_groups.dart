import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import 'watch_history.dart';

class LiveFavouriteGroup {
  final String id, name;
  final List<String> channels;
  const LiveFavouriteGroup(this.id, this.name, this.channels);
}

/// Group metadata never changes the provider's categories or saved favourites.
class LiveFavouriteGroups extends ChangeNotifier {
  static const all = '__all__', ungrouped = '__ungrouped__';
  static final _instances = Expando<LiveFavouriteGroups>();
  static LiveFavouriteGroups forProvider(IptvProvider provider) =>
      _instances[provider] ??= LiveFavouriteGroups(
        WatchHistory.forProvider(provider).scope,
      );
  final String scope;
  final FlutterSecureStorage storage;
  LiveFavouriteGroups(
    this.scope, {
    this.storage = const FlutterSecureStorage(),
  });
  List<LiveFavouriteGroup> _groups = [];
  Map<String, List<String>> _orders = {};
  List<LiveFavouriteGroup> get groups => List.unmodifiable(_groups);
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  String get key => 'live_favourite_groups:$scope';
  Future<void> load() => _loading ??= () async {
    final saved = await storage.read(key: key);
    if (saved != null) _restore(jsonDecode(saved) as Map<String, dynamic>);
  }();
  void _restore(Map<String, dynamic> data) {
    _groups = (data['groups'] as List? ?? [])
        .map(
          (row) => LiveFavouriteGroup(
            row['id'],
            row['name'],
            List<String>.unmodifiable((row['channels'] as List).cast<String>()),
          ),
        )
        .toList();
    _orders = (data['orders'] as Map? ?? {}).map(
      (key, value) => MapEntry(key as String, (value as List).cast<String>()),
    );
  }

  Map<String, dynamic> _json() => {
    'groups': _groups
        .map(
          (group) => {
            'id': group.id,
            'name': group.name,
            'channels': group.channels,
          },
        )
        .toList(),
    'orders': _orders,
  };
  Future<T> _change<T>(T Function() mutate) async {
    await load();
    final next = _writes.then((_) async {
      final previous = jsonDecode(jsonEncode(_json())) as Map<String, dynamic>;
      try {
        final result = mutate();
        await storage.write(key: key, value: jsonEncode(_json()));
        notifyListeners();
        return result;
      } catch (_) {
        _restore(previous);
        rethrow;
      }
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  String _name(String input, {String? except}) {
    final name = input.trim();
    if (name.isEmpty || name.length > 40) {
      throw const ProviderException(
        'Use a group name between 1 and 40 characters.',
      );
    }
    if (['all channels', 'ungrouped'].contains(name.toLowerCase()) ||
        _groups.any(
          (group) =>
              group.id != except &&
              group.name.toLowerCase() == name.toLowerCase(),
        )) {
      throw const ProviderException('Choose a different group name.');
    }
    return name;
  }

  String name(String id) => id == all
      ? 'All channels'
      : id == ungrouped
      ? 'Ungrouped'
      : _groups.where((group) => group.id == id).firstOrNull?.name ??
            'All channels';
  bool exists(String id) =>
      id == all || id == ungrouped || _groups.any((group) => group.id == id);
  Future<String> create(String input) => _change(() {
    final name = _name(input);
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 30)}';
    _groups = [..._groups, LiveFavouriteGroup(id, name, const [])];
    return id;
  });
  Future<void> rename(String id, String input) => _change(() {
    final name = _name(input, except: id);
    _groups = _groups
        .map(
          (group) => group.id == id
              ? LiveFavouriteGroup(id, name, group.channels)
              : group,
        )
        .toList();
  });
  Future<void> delete(String id) => _change(() {
    _groups = _groups.where((group) => group.id != id).toList();
    _orders.remove(id);
  });
  Set<String> memberships(String channel) => _groups
      .where((group) => group.channels.contains(channel))
      .map((group) => group.id)
      .toSet();
  Future<void> assign(String channel, Set<String> selected) => _change(() {
    _groups = _groups.map((group) {
      if (selected.contains(group.id) == group.channels.contains(channel)) {
        return group;
      }
      final channels = group.channels.where((id) => id != channel).toList();
      if (selected.contains(group.id)) channels.add(channel);
      return LiveFavouriteGroup(
        group.id,
        group.name,
        List.unmodifiable(channels),
      );
    }).toList();
  });
  Future<void> moveGroup(String id, int delta) => _change(() {
    final index = _groups.indexWhere((group) => group.id == id),
        next = _groups.indexWhere((group) => group.id == id) + delta;
    if (index < 0 || next < 0 || next >= _groups.length) return;
    final updated = List<LiveFavouriteGroup>.of(_groups);
    final entry = updated.removeAt(index);
    updated.insert(next, entry);
    _groups = updated;
  });
  List<ContentItem> channels(String selected, List<ContentItem> favourites) {
    final id = exists(selected) ? selected : all;
    final assigned = _groups.expand((group) => group.channels).toSet();
    final ids =
        _groups
            .where((group) => group.id == id)
            .firstOrNull
            ?.channels
            .toSet() ??
        <String>{};
    final rows = favourites
        .where(
          (item) =>
              item.type == ContentType.live &&
              (id == all ||
                  (id == ungrouped
                      ? !assigned.contains(item.id)
                      : ids.contains(item.id))),
        )
        .toList();
    final order =
        _orders[id] ??
        (id == all || id == ungrouped ? <String>[] : ids.toList());
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final fallback = {
      for (var i = 0; i < rows.length; i++) rows[i].id: order.length + i,
    };
    rows.sort(
      (a, b) => (rank[a.id] ?? fallback[a.id]!).compareTo(
        rank[b.id] ?? fallback[b.id]!,
      ),
    );
    return rows;
  }

  Future<void> moveChannel(
    String groupId,
    String channel,
    int delta,
    List<ContentItem> favourites,
  ) => _change(() {
    final id = exists(groupId) ? groupId : all;
    final order = channels(id, favourites).map((item) => item.id).toList();
    final index = order.indexOf(channel), next = order.indexOf(channel) + delta;
    if (index < 0 || next < 0 || next >= order.length) return;
    order.removeAt(index);
    order.insert(next, channel);
    _orders[id] = order;
  });
}
