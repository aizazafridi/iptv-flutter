import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/data/subtitle_settings.dart';
import 'package:iptv_flutter/data/subtitle_preferences.dart';
import 'package:iptv_flutter/data/playback_preferences.dart';
import 'package:iptv_flutter/data/locked_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/playback/subtitle_customization.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'widget_test.dart' show FakeProvider;

ProviderConfig config(String username) => ProviderConfig(
  providerId: 'fixture',
  server: 'https://example.com',
  username: username,
  password: 'fixture',
);
ProviderRegistry registry() =>
    ProviderRegistry()..register('fixture', 'Fixture', (_) => FakeProvider());

class CatalogFixture extends FakeProvider {
  @override
  Future<List<Category>> getCategories(ContentType type) async => [
    Category('7', 'English (4K)', type),
    Category('9', 'Other', type),
  ];
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    ContentItem(id: '42', name: 'Locked title', type: type, categoryId: '7'),
    ContentItem(id: '88', name: 'Open title', type: type, categoryId: '9'),
  ];
  @override
  Future<List<ContentItem>> getItems(Category category) async =>
      (await getAllItems(
        category.type,
      )).where((item) => item.categoryId == category.id).toList();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'startup migrates the existing account and waits for explicit profile selection',
    () async {
      const store = CredentialStore();
      final original = config('legacy');
      await store.save(original);
      await store.storage.write(key: 'app_background', value: 'Navy');
      await store.storage.write(
        key: 'opensubtitles_api_key',
        value: 'legacy-key',
      );
      final appearance = AppAppearance();
      final session = Session(registry(), store, appearance: appearance);
      await session.initialize();
      expect(session.account, isNull);
      expect(session.profiles.single.name, 'legacy');
      expect(session.profiles.single.id, WatchHistory.scopeFor(original));
      await session.selectProfile(session.profiles.single);
      expect(session.account, isNotNull);
      expect(appearance.selected, 'Navy');
      expect(
        await SubtitleSettings(scope: session.activeProfile!.id).load(),
        'legacy-key',
      );
      await session.signOut();
      expect((await store.loadProfiles())!.length, 1);
      session.dispose();
      appearance.dispose();
    },
  );
  test(
    'five profiles persist names and avatars; a sixth is rejected',
    () async {
      const store = CredentialStore();
      final session = Session(registry(), store);
      await session.initialize();
      for (var index = 0; index < 5; index++) {
        await session.connect(
          config('user$index'),
          name: 'Viewer $index',
          avatar: index + 1,
        );
      }
      expect(session.profiles.length, 5);
      await session.connect(config('sixth'), name: 'Sixth', avatar: 9);
      expect(session.profiles.length, 5);
      expect(session.error, contains('five'));
      final reloaded = Session(registry(), store);
      await reloaded.initialize();
      expect(reloaded.account, isNull);
      expect(reloaded.profiles.last.name, 'Viewer 4');
      expect(reloaded.profiles.last.avatar, 5);
      await reloaded.removeProfile(reloaded.profiles.first);
      expect((await store.loadProfiles())!.length, 4);
      await reloaded.connect(
        config('last-avatar'),
        name: 'Final avatar',
        avatar: 7,
      );
      expect((await store.loadProfiles())!.last.avatar, 7);
      session.dispose();
      reloaded.dispose();
    },
  );
  test(
    'each profile keeps independent appearance, subtitles, playback and lock settings',
    () async {
      final appearance = AppAppearance();
      final session = Session(
        registry(),
        const CredentialStore(),
        appearance: appearance,
      );
      await session.initialize();
      await session.connect(config('one'), name: 'One', avatar: 1);
      final first = session.activeProfile!;
      await appearance.choose('Forest');
      await appearance.setCards(ContentType.movies, true);
      await SubtitleSettings(scope: first.id).save('first-key');
      await SubtitlePreferences(
        scope: first.id,
      ).saveAppearance(const SubtitleAppearance(size: 32, color: 'Yellow'));
      await PlaybackPreferences(first.id).save({'seek': 120, 'rate': 2});
      await CategoryLocks.forProvider(session.provider!).setPassword('123456');
      const favourite = ContentItem(
        id: '42',
        name: 'Saved movie',
        type: ContentType.movies,
        categoryId: '9',
      );
      await MyList.forProvider(session.provider!).toggle(favourite);
      await WatchHistory.forProvider(session.provider!).save(
        WatchEntry(
          favourite,
          null,
          const Duration(minutes: 2),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      await session.signOut();
      await session.connect(config('two'), name: 'Two', avatar: 2);
      final second = session.activeProfile!;
      expect(appearance.selected, 'Midnight');
      expect(appearance.usesCards(ContentType.movies), isFalse);
      expect(await SubtitleSettings(scope: second.id).load(), isEmpty);
      expect(
        (await SubtitlePreferences(scope: second.id).loadAppearance()).color,
        'White',
      );
      expect(await PlaybackPreferences(second.id).load(), isEmpty);
      expect(CategoryLocks.forProvider(session.provider!).hasPassword, isFalse);
      expect(
        await MyList.forProvider(session.provider!).items(ContentType.movies),
        isEmpty,
      );
      expect(
        await WatchHistory.forProvider(session.provider!).entries(),
        isEmpty,
      );
      await appearance.choose('Plum');
      await session.signOut();
      await session.selectProfile(first);
      expect(appearance.selected, 'Forest');
      expect(appearance.usesCards(ContentType.movies), isTrue);
      expect(await SubtitleSettings(scope: first.id).load(), 'first-key');
      expect(
        CategoryLocks.forProvider(session.provider!).check('123456'),
        isTrue,
      );
      session.dispose();
      appearance.dispose();
    },
  );
  test(
    'locks prevent catalog, detail and playback bypasses for every content type',
    () async {
      for (final type in ContentType.values) {
        final locks = CategoryLocks(type.name);
        final guarded = LockedProvider(CatalogFixture(), locks);
        await locks.setPassword('123456');
        final category = Category('7', 'Locked', type);
        await locks.setLocked(category, true);
        final item = ContentItem(
          id: '42',
          name: 'Locked title',
          type: type,
          categoryId: '7',
        );
        expect((await guarded.getAllItems(type)).single.id, '88');
        final legacy = await guarded.visibleSavedItems([
          ContentItem(id: '42', name: 'Saved locked', type: type),
          ContentItem(id: '88', name: 'Saved open', type: type),
        ]);
        expect(legacy.single.id, '88');
        await expectLater(
          guarded.getItems(category),
          throwsA(isA<ProviderException>()),
        );
        await expectLater(
          guarded.resolvePlayback(item),
          throwsA(isA<ProviderException>()),
        );
        if (type == ContentType.movies) {
          await expectLater(
            guarded.getMovieDetails(item),
            throwsA(isA<ProviderException>()),
          );
        }
        if (type == ContentType.series) {
          await expectLater(
            guarded.getSeriesDetails(item),
            throwsA(isA<ProviderException>()),
          );
        }
        expect(locks.unlock(category, 'wrong'), isFalse);
        expect(locks.unlock(category, '123456'), isTrue);
        expect((await guarded.getAllItems(type)).length, 2);
        final restored = CategoryLocks(type.name);
        await restored.load();
        expect(restored.isLocked(category), isTrue);
        await expectLater(
          restored.setPassword('567890', current: 'wrong'),
          throwsA(isA<ProviderException>()),
        );
        await restored.setLocked(category, false, password: '123456');
        expect(restored.configured(category), isFalse);
        guarded.dispose();
      }
    },
  );
  testWidgets(
    'startup shows named avatars and add-account offers all available avatars',
    (tester) async {
      final session = Session(registry(), const CredentialStore());
      await session.initialize();
      await session.connect(config('saved'), name: 'Alex', avatar: 4);
      await session.signOut();
      final appearance = AppAppearance();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).index, 4);
      expect(find.text('Add account'), findsNothing);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileAvatar), findsNWidgets(profileAvatarCount));
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
  testWidgets(
    'locked category prompts for its password and rejects an incorrect password',
    (tester) async {
      final locks = CategoryLocks('lock-ui');
      await locks.setPassword('123456');
      await locks.setLocked(
        const Category('7', 'English (4K)', ContentType.movies),
        true,
      );
      final provider = LockedProvider(CatalogFixture(), locks);
      CategoryLocks.attach(provider, locks);
      await tester.pumpWidget(
        MaterialApp(
          home: BrowseScreen(provider: provider, type: ContentType.movies),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('English (4K)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'wrong');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect lock password.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Locked title'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
