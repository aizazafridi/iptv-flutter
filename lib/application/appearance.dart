import 'dart:convert';
import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppAppearance extends ChangeNotifier {
  static const backgrounds = <String, Color>{
    'Midnight': Color(0xff11101c),
    'Black': Color(0xff090909),
    'Navy': Color(0xff101d35),
    'Forest': Color(0xff10271e),
    'Plum': Color(0xff29162e),
    'Light': Color(0xfff3f2f7),
  };
  final FlutterSecureStorage storage;
  AppAppearance({this.storage = const FlutterSecureStorage()});
  String selected = 'Midnight';
  final Set<ContentType> cardViews = {};
  bool usesCards(ContentType type) => cardViews.contains(type);
  String? error;
  bool _disposed = false;
  String? scope;
  String key(String name) => scope == null ? name : '$name:$scope';
  Future<void> activate(String? profileId, {bool migrateLegacy = false}) async {
    scope = profileId;
    selected = 'Midnight';
    cardViews.clear();
    error = null;
    if (profileId != null && migrateLegacy) {
      for (final name in ['app_background', 'app_card_views']) {
        if (await storage.read(key: key(name)) == null) {
          final legacy = await storage.read(key: name);
          if (legacy != null) {
            await storage.write(key: key(name), value: legacy);
          }
        }
      }
    }
    if (profileId != null) {
      await load();
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  Color get background => backgrounds[selected]!;
  Brightness get brightness =>
      background.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark;

  Future<void> load() async {
    try {
      final saved = await storage.read(key: key('app_background'));
      if (_disposed) return;
      if (backgrounds.containsKey(saved)) selected = saved!;
      final layout = await storage.read(key: key('app_card_views'));
      if (_disposed) return;
      if (layout != null) {
        final names = jsonDecode(layout);
        if (names is List) {
          cardViews.addAll(
            ContentType.values.where((type) => names.contains(type.name)),
          );
        }
      }
    } catch (_) {
      // Use the default theme if the saved preference cannot be read.
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> choose(String name) async {
    if (!backgrounds.containsKey(name)) return;
    selected = name;
    error = null;
    notifyListeners();
    try {
      await storage.write(key: key('app_background'), value: name);
    } catch (_) {
      if (!_disposed) {
        error = 'Color changed, but could not be saved. Please retry.';
        notifyListeners();
      }
    }
  }

  Future<void> setCards(ContentType type, bool enabled) async {
    if (enabled) {
      cardViews.add(type);
    } else {
      cardViews.remove(type);
    }
    error = null;
    notifyListeners();
    try {
      await storage.write(
        key: key('app_card_views'),
        value: jsonEncode(cardViews.map((type) => type.name).toList()),
      );
    } catch (_) {
      if (!_disposed) {
        error = 'View changed, but could not be saved. Please retry.';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
