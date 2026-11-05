import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_zap_channels.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'live_channel_browser_test.dart' show BrowserProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'zapping follows the selected custom group and its independent order',
    () async {
      final p = BrowserProvider();
      final list = MyList.forProvider(p);
      final group = await list.groups.create('Sports');
      for (final i in [0, 2, 4]) {
        await list.saveLiveMembership(p.channels[i], {group}, general: false);
      }
      await list.groups.reorderChannels(group, ['4', '0', '2'], p.channels);
      final result = await liveZapChannels(
        provider: p,
        load: () async => p.channels,
        categoryId: 'favorites',
        groupId: group,
      );
      expect(result.map((c) => c.id), ['4', '0', '2']);
      expect(result.any((c) => c.id == '1'), isFalse);
      p.dispose();
    },
  );
  test('native category is used instead of the full playlist', () async {
    final p = BrowserProvider();
    var fullCalls = 0;
    final result = await liveZapChannels(
      provider: p,
      load: () async {
        fullCalls++;
        return p.channels;
      },
      categoryId: 'sports',
    );
    expect(result.single.id, 'sports-1');
    expect(fullCalls, 0);
    expect(
      (await liveZapChannels(
        provider: p,
        load: () async => p.channels,
        categoryId: 'all',
      )).length,
      120,
    );
    p.dispose();
  });
}
