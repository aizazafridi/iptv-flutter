import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'live_favourite_groups_test.dart' show channels;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'custom union, independent orders, removal and profile isolation',
    () async {
      final list = MyList('union');
      final groups = list.groups;
      final a = await groups.create('A'), b = await groups.create('B');
      for (final c in channels) {
        await list.saveLiveMembership(c, {a, b}, general: false);
      }
      expect(await list.items(ContentType.live), hasLength(3));
      await groups.reorderChannels(a, ['3', '1', '2'], channels);
      expect(groups.channels(a, channels).map((c) => c.id), ['3', '1', '2']);
      expect(groups.channels(b, channels).map((c) => c.id), ['1', '2', '3']);
      await groups.rename(a, 'Renamed');
      await groups.reorderGroups([b, a]);
      final restored = MyList('union');
      await restored.load();
      expect(restored.groups.groups.map((g) => g.id), [b, a]);
      expect(restored.groups.name(a), 'Renamed');
      await groups.delete(a);
      expect(await list.items(ContentType.live), hasLength(3));
      await groups.delete(b);
      expect(await list.items(ContentType.live), isEmpty);
      expect(await MyList('other').items(ContentType.live), isEmpty);
    },
  );
  test(
    'legacy favorites remain general and interrupted writes recover',
    () async {
      final legacy = jsonEncode([
        {'id': '1', 'name': 'One', 'type': 'live'},
      ]);
      const storage = FlutterSecureStorage();
      await storage.write(key: 'my_list:legacy', value: legacy);
      await storage.write(
        key: 'live_membership_transaction:legacy',
        value: jsonEncode({'groups': null, 'list': legacy}),
      );
      await storage.write(key: 'my_list:legacy', value: '[]');
      await storage.write(
        key: 'live_favourite_groups:legacy',
        value: jsonEncode({
          'groups': [],
          'orders': {},
          'general': {'1': false},
        }),
      );
      final list = MyList('legacy');
      expect(await list.items(ContentType.live), hasLength(1));
      expect(list.groups.generalContains('1', saved: true), isTrue);
      expect(await storage.read(key: list.groups.transactionKey), isNull);
      final id = await list.groups.create('Custom');
      await list.saveLiveMembership(channels.first, {id}, general: true);
      await list.groups.delete(id);
      expect(await list.items(ContentType.live), hasLength(1));
    },
  );
  test(
    'failed persistence restores membership in memory and storage',
    () async {
      final list = MyList('failure');
      final groups = list.groups;
      final id = await groups.create('Keep');
      await list.saveLiveMembership(channels.first, {id}, general: true);
      const storage = FlutterSecureStorage();
      final before = await storage.read(key: groups.key);
      await expectLater(
        groups.commitMembership('1', {}, false, (_) async {
          throw StateError('write failed');
        }),
        throwsStateError,
      );
      expect(groups.memberships('1'), {id});
      expect(groups.generalContains('1', saved: true), isTrue);
      expect(await storage.read(key: groups.key), before);
      expect(list.contains(channels.first), isTrue);
    },
  );
}
