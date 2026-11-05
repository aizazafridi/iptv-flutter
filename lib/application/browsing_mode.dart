import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum BrowsingMode { premium, lite }

/// Device-wide resource preference; deliberately independent of account/profile.
class BrowsingModeSettings extends ChangeNotifier {
  static final instance = BrowsingModeSettings();
  final FlutterSecureStorage storage;
  BrowsingModeSettings({this.storage = const FlutterSecureStorage()});
  BrowsingMode mode = BrowsingMode.premium;
  bool get lite => mode == BrowsingMode.lite;
  String? error;
  Future<void> load() async {
    try {
      mode = await storage.read(key: 'browsing_mode') == 'lite'
          ? BrowsingMode.lite
          : BrowsingMode.premium;
    } catch (_) {
      mode = BrowsingMode.premium;
    }
    notifyListeners();
  }

  Future<void> choose(BrowsingMode value) async {
    try {
      await storage.write(key: 'browsing_mode', value: value.name);
      error = null;
      mode = value;
    } catch (_) {
      error = 'Could not save browsing mode. Please retry.';
    }
    notifyListeners();
  }
}
