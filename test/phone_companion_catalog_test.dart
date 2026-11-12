import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/phone_companion_catalog.dart';
import 'package:iptv_flutter/application/phone_companion_server.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'widget_test.dart' show FakeProvider;

class PhoneCatalogProvider extends FakeProvider {
  int resolves = 0;
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async {
    catalogCalls++;
    return List.generate(
      45,
      (i) => ContentItem(
        id: '$i',
        name: 'Title $i',
        type: type,
        categoryId: i == 1 ? 'locked' : 'open',
        artwork: Uri.parse('https://secret:password@example.test/$i'),
      ),
    );
  }

  @override
  Future<PlaybackSource> resolvePlayback(
    ContentItem item, {
    Episode? episode,
  }) async {
    resolves++;
    return super.resolvePlayback(item, episode: episode);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'search pages share cached catalog and never expose URLs or start streams',
    () async {
      final provider = PhoneCatalogProvider();
      final api = PhoneCompanionCatalog(
        provider,
        isActive: () => true,
        onOpen: (_, _) async {},
      );
      final first =
          await api.dispatch('/search', {'type': 'movies', 'query': 'title'})
              as Map;
      final next =
          await api.dispatch('/search', {
                'type': 'movies',
                'query': 'title',
                'offset': 40,
              })
              as Map;
      expect((first['items'] as List).length, 40);
      expect((next['items'] as List).length, 5);
      expect(first['more'], true);
      expect(first.toString(), isNot(contains('password')));
      expect(first.toString(), isNot(contains('https://')));
      expect(provider.catalogCalls, 1);
      expect(provider.detailCalls, 0);
      expect(provider.resolves, 0);
    },
  );
  test(
    'hidden, locked and Kids-disallowed titles cannot be listed or sent',
    () async {
      final provider = PhoneCatalogProvider();
      final locks = CategoryLocks('phone-restrictions');
      CategoryLocks.attach(provider, locks);
      await locks.setPassword('123456');
      await locks.configureCategory(
        const Category('locked', '', ContentType.movies),
        true,
      );
      final hidden = ContentItem(
        id: '2',
        name: 'Title 2',
        type: ContentType.movies,
        categoryId: 'open',
      );
      await locks.setTitleHidden(hidden, true);
      final api = PhoneCompanionCatalog(
        provider,
        isActive: () => true,
        onOpen: (_, _) async => fail('Restricted title must not reach TV'),
      );
      final result =
          await api.dispatch('/search', {'type': 'movies', 'query': ''}) as Map;
      final ids = (result['items'] as List).map((r) => r['id']);
      expect(ids, isNot(contains('1')));
      expect(ids, isNot(contains('2')));
      for (final id in ['1', '2', 'unknown']) {
        await expectLater(
          api.dispatch('/open', {'type': 'movies', 'id': id}),
          throwsA(isA<CompanionError>()),
        );
        await expectLater(
          api.dispatch('/favourite', {
            'type': 'movies',
            'id': id,
            'saved': true,
          }),
          throwsA(isA<CompanionError>()),
        );
      }
      await locks.setProfilePolicy(
        kids: true,
        requirePin: false,
        allowed: {},
        pin: '123456',
      );
      final kids =
          await api.dispatch('/search', {'type': 'movies', 'query': ''}) as Map;
      expect(kids['items'], isEmpty);
    },
  );
  test(
    'explicit favourite commands are idempotent and share TV My List',
    () async {
      final provider = PhoneCatalogProvider();
      final api = PhoneCompanionCatalog(
        provider,
        isActive: () => true,
        onOpen: (_, _) async {},
      );
      final request = {'type': 'movies', 'id': '0', 'saved': true};
      await api.dispatch('/favourite', request);
      await api.dispatch('/favourite', request);
      expect(
        (await MyList.forProvider(provider).items(ContentType.movies)).length,
        1,
      );
      final list = await api.dispatch('/list', {'type': 'movies'}) as Map;
      expect((list['items'] as List).single['id'], '0');
      await api.dispatch('/favourite', {...request, 'saved': false});
      expect(
        await MyList.forProvider(provider).items(ContentType.movies),
        isEmpty,
      );
    },
  );
  test(
    'channel membership and groups reuse the existing shared group store',
    () async {
      final provider = PhoneCatalogProvider();
      final api = PhoneCompanionCatalog(
        provider,
        isActive: () => true,
        onOpen: (_, _) async {},
      );
      await api.dispatch('/group', {'action': 'create', 'name': 'Sports'});
      final groups = await api.dispatch('/groups', {}) as Map;
      final id = (groups['groups'] as List).single['id'];
      await api.dispatch('/membership', {
        'type': 'live',
        'id': '0',
        'general': false,
        'groups': [id],
      });
      final saved = MyList.forProvider(provider);
      expect(saved.groups.memberships('0'), {id});
      expect((await saved.items(ContentType.live)).single.id, '0');
      await api.dispatch('/group', {
        'action': 'rename',
        'id': id,
        'name': 'My Sports',
      });
      expect(saved.groups.groups.single.name, 'My Sports');
    },
  );
  test(
    'send resolves canonical item and preserves play vs open intent',
    () async {
      final provider = PhoneCatalogProvider();
      ContentItem? received;
      bool? play;
      var active = true;
      final api = PhoneCompanionCatalog(
        provider,
        isActive: () => active,
        onOpen: (item, requested) async {
          received = item;
          play = requested;
        },
      );
      await api.dispatch('/open', {
        'type': 'movies',
        'id': '0',
        'name': 'Injected',
        'play': true,
      });
      expect(received?.name, 'Title 0');
      expect(play, true);
      expect(provider.resolves, 0);
      active = false;
      await expectLater(
        api.dispatch('/open', {'type': 'movies', 'id': '0'}),
        throwsA(isA<CompanionError>()),
      );
    },
  );
}
