import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_favourite_groups.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/domain/models.dart';

const channels = [
  ContentItem(id: '1', name: 'One', type: ContentType.live),
  ContentItem(id: '2', name: 'Two', type: ContentType.live),
  ContentItem(id: '3', name: 'Three', type: ContentType.live),
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'group assignments persist per profile and support multiple groups',
    () async {
      final groups = LiveFavouriteGroups('alice');
      final sports = await groups.create('Sports'),
          news = await groups.create('News');
      await groups.assign('1', {sports, news});
      await groups.assign('2', {sports});
      final restored = LiveFavouriteGroups('alice');
      await restored.load();
      expect(restored.channels(sports, channels).map((item) => item.id), [
        '1',
        '2',
      ]);
      expect(restored.channels(news, channels).single.id, '1');
      expect(
        restored.channels(LiveFavouriteGroups.ungrouped, channels).single.id,
        '3',
      );
      final other = LiveFavouriteGroups('bob');
      await other.load();
      expect(other.groups, isEmpty);
      expect(
        other.channels(LiveFavouriteGroups.ungrouped, channels),
        hasLength(3),
      );
      await restored.assign('1', {});
      expect(restored.channels(news, channels), isEmpty);
    },
  );
  test('renaming and deleting groups preserve the saved favourites', () async {
    final list = MyList('alice');
    for (final channel in channels) {
      await list.toggle(channel);
    }
    final groups = LiveFavouriteGroups('alice');
    final id = await groups.create('Sports');
    await groups.assign('1', {id});
    await groups.rename(id, 'Matches');
    expect(groups.name(id), 'Matches');
    await groups.delete(id);
    expect(await list.items(ContentType.live), hasLength(3));
    expect(
      groups.channels(LiveFavouriteGroups.ungrouped, channels),
      hasLength(3),
    );
    expect(groups.channels(id, channels), hasLength(3));
  });
  test('group order and per-group channel order survive reload', () async {
    final groups = LiveFavouriteGroups('alice');
    final first = await groups.create('First'),
        second = await groups.create('Second');
    for (final item in channels) {
      await groups.assign(item.id, {first});
    }
    await groups.moveGroup(second, -1);
    await groups.moveChannel(first, '3', -1, channels);
    await groups.moveChannel(LiveFavouriteGroups.all, '1', 1, channels);
    final restored = LiveFavouriteGroups('alice');
    await restored.load();
    expect(restored.groups.first.id, second);
    expect(restored.channels(first, channels).map((item) => item.id), [
      '1',
      '3',
      '2',
    ]);
    expect(
      restored
          .channels(LiveFavouriteGroups.all, channels)
          .map((item) => item.id),
      ['2', '1', '3'],
    );
    await restored.assign('1', {first});
    expect(restored.channels(first, channels).map((item) => item.id), [
      '1',
      '3',
      '2',
    ]);
  });
  test(
    'invalid names are rejected and concurrent edits are serialized',
    () async {
      final groups = LiveFavouriteGroups('alice');
      await groups.create('Sports');
      for (final name in [
        '',
        '   ',
        'sports',
        'All channels',
        'Ungrouped',
        'a' * 41,
      ]) {
        await expectLater(
          groups.create(name),
          throwsA(isA<ProviderException>()),
        );
      }
      await Future.wait([groups.create('News'), groups.create('Kids')]);
      final restored = LiveFavouriteGroups('alice');
      await restored.load();
      expect(restored.groups, hasLength(3));
    },
  );
  test('groups never resurrect removed or hidden channels', () async {
    final groups = LiveFavouriteGroups('alice');
    final id = await groups.create('Saved');
    await groups.assign('1', {id});
    await groups.assign('2', {id});
    expect(groups.channels(id, [channels.last]), isEmpty);
    expect(groups.channels(id, [channels.first]).single.id, '1');
    expect(
      groups.channels(LiveFavouriteGroups.all, [
        const ContentItem(id: '1', name: 'Movie', type: ContentType.movies),
      ]),
      isEmpty,
    );
  });
}
