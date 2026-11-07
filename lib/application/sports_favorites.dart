import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SportsFavorites extends ChangeNotifier {
  final String scope;
  final FlutterSecureStorage storage;
  SportsFavorites(this.scope, {this.storage = const FlutterSecureStorage()});
  bool closed = false;
  @override
  void dispose() {
    closed = true;
    super.dispose();
  }

  Map<String, String> teams = {}, leagues = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  String get key => 'sports_favorites_v1:$scope';
  Future<void> load() => _loading ??= () async {
    final raw = await storage.read(key: key);
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      teams = Map<String, String>.from(data['teams'] as Map? ?? {});
      leagues = Map<String, String>.from(data['leagues'] as Map? ?? {});
    }
  }();
  Future<void> toggle(String id, String name, {bool league = false}) {
    final result = _writes.then((_) async {
      await load();
      final nextTeams = Map<String, String>.from(teams);
      final nextLeagues = Map<String, String>.from(leagues);
      final target = league ? nextLeagues : nextTeams;
      if (target.containsKey(id)) {
        target.remove(id);
      } else {
        target[id] = name;
      }
      await storage.write(
        key: key,
        value: jsonEncode({'teams': nextTeams, 'leagues': nextLeagues}),
      );
      teams = nextTeams;
      leagues = nextLeagues;
      if (!closed) notifyListeners();
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
