import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../playback/subtitle_customization.dart';

class SubtitlePreferences {
  final FlutterSecureStorage storage;
  final String? scope;
  String get appearanceKey =>
      scope == null ? 'subtitle_appearance' : 'subtitle_appearance:$scope';
  const SubtitlePreferences({
    this.storage = const FlutterSecureStorage(),
    this.scope,
  });
  Future<Map<String, dynamic>?> loadChoice(String scope) async {
    try {
      final saved = await storage.read(key: 'subtitle_choice:$scope');
      return saved == null ? null : jsonDecode(saved) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveChoice(String scope, Map<String, dynamic> choice) async {
    await storage.write(
      key: 'subtitle_choice:$scope',
      value: jsonEncode(choice),
    );
  }

  Future<SubtitleAppearance> loadAppearance() async {
    try {
      final saved = await storage.read(key: appearanceKey);
      final value = saved == null
          ? <String, dynamic>{}
          : jsonDecode(saved) as Map<String, dynamic>;
      return SubtitleAppearance(
        size: (value['size'] as num?)?.toDouble() ?? 24,
        color: SubtitleAppearance.colors.containsKey(value['color'])
            ? value['color']
            : 'White',
        position: ['Top', 'Middle', 'Bottom'].contains(value['position'])
            ? value['position']
            : 'Bottom',
      );
    } catch (_) {
      return const SubtitleAppearance();
    }
  }

  Future<void> saveAppearance(SubtitleAppearance appearance) => storage.write(
    key: appearanceKey,
    value: jsonEncode({
      'size': appearance.size,
      'color': appearance.color,
      'position': appearance.position,
    }),
  );
}
