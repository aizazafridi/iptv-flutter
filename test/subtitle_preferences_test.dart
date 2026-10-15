import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/subtitle_preferences.dart';
import 'package:iptv_flutter/playback/subtitle_customization.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'subtitle selection persists per account and episode without an expiring URL',
    () async {
      const preferences = SubtitlePreferences();
      await preferences.saveChoice('account:series:42:episode1', {
        'kind': 'online',
        'fileId': 123,
        'name': 'English release',
      });
      final restored = await const SubtitlePreferences().loadChoice(
        'account:series:42:episode1',
      );
      expect(restored!['fileId'], 123);
      expect(restored['name'], 'English release');
      expect(restored.containsKey('url'), isFalse);
      expect(
        await preferences.loadChoice('account:series:42:episode2'),
        isNull,
      );
      expect(
        await preferences.loadChoice('another-account:series:42:episode1'),
        isNull,
      );
    },
  );
  test('subtitle appearance and off choice survive reload', () async {
    const preferences = SubtitlePreferences();
    await preferences.saveAppearance(
      const SubtitleAppearance(size: 32, color: 'Yellow', position: 'Top'),
    );
    await preferences.saveChoice('movie', {'kind': 'track', 'id': 'no'});
    final appearance = await const SubtitlePreferences().loadAppearance();
    expect(appearance.size, 32);
    expect(appearance.color, 'Yellow');
    expect(appearance.position, 'Top');
    expect((await preferences.loadChoice('movie'))!['id'], 'no');
  });
}
