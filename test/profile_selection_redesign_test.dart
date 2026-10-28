import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/lock_password_dialog.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/data/locked_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/profile_selection_screen.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'profiles_locks_test.dart' show registry, config;
import 'widget_test.dart' show FakeProvider;

List<AccountProfile> profiles(int count) => List.generate(
  count,
  (i) => AccountProfile(
    id: 'profile-$i',
    name: 'Viewer $i',
    avatar: i,
    config: config('viewer$i'),
  ),
);

class KidsFixture extends FakeProvider {
  static const safe = ContentItem(
    id: 'safe',
    name: 'Allowed channel',
    type: ContentType.live,
    categoryId: '7',
  );
  static const adult = ContentItem(
    id: 'adult',
    name: 'Blocked channel',
    type: ContentType.live,
    categoryId: '9',
  );
  @override
  Future<List<Category>> getCategories(ContentType type) async => [
    Category('7', 'Kids', type),
    Category('9', 'Other', type),
  ];
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    safe,
    adult,
    const ContentItem(
      id: 'unknown',
      name: 'No category',
      type: ContentType.live,
    ),
  ];
  @override
  Future<List<ContentItem>> getItems(Category category) async =>
      category.id == '7' ? [safe] : [adult];
}

void main() {
  testWidgets(
    'protected profile requires its PIN before opening the dashboard',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = Session(registry(), const CredentialStore());
      await session.initialize();
      await session.connect(config('protected'), name: 'Protected');
      final id = session.activeProfile!.id;
      await session.signOut();
      await CategoryLocks(id).setProfilePolicy(
        kids: false,
        requirePin: true,
        allowed: {},
        pin: '123456',
      );
      final appearance = AppAppearance();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.byType(LockPasswordDialog), findsOneWidget);
      expect(session.account, isNull);
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(session.activeProfile?.id, id);
      expect(find.byType(LockPasswordDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'five TV profiles fit in one row, last-used focus and management mode work',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final managed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ProfileSelectionScreen(
            profiles: profiles(5),
            lastProfileId: 'profile-2',
            onSelect: (_) async {},
            onManage: (p) async => managed.add(p.id),
            onAdd: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'profile profile-2',
      );
      final avatars = tester
          .widgetList<ProfileAvatar>(find.byType(ProfileAvatar))
          .toList();
      expect(avatars, hasLength(5));
      expect(
        avatars.every((avatar) => avatar.roundedSquare && avatar.size == 150),
        isTrue,
      );
      final y = tester.getCenter(find.byType(ProfileAvatar).first).dy;
      for (var i = 1; i < 5; i++) {
        expect(
          tester.getCenter(find.byType(ProfileAvatar).at(i)).dy,
          closeTo(y, .1),
        );
      }
      expect(find.text('Add profile'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(5));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(managed, ['profile-2']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'profile activation waits for the short transition; Add profile remains available',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: false);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProfileSelectionScreen(
            profiles: profiles(2),
            onSelect: (_) async {
              selected++;
            },
            onManage: (_) async {},
            onAdd: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add profile'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 200));
      expect(selected, 0);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'Kids allowlist filters catalogues and rejects direct playback and details',
    () async {
      final locks = CategoryLocks('kids');
      await locks.setProfilePolicy(
        kids: true,
        requirePin: false,
        allowed: {'live:7'},
        pin: '123456',
      );
      final provider = LockedProvider(KidsFixture(), locks);
      await provider.connect();
      expect(
        (await provider.getCategories(ContentType.live)).map((c) => c.id),
        ['7'],
      );
      expect((await provider.getAllItems(ContentType.live)).map((c) => c.id), [
        'safe',
      ]);
      await expectLater(
        provider.getItems(const Category('9', 'Other', ContentType.live)),
        throwsA(isA<ProviderException>()),
      );
      await expectLater(
        provider.resolvePlayback(KidsFixture.adult),
        throwsA(isA<ProviderException>()),
      );
      await expectLater(
        provider.getMovieDetails(KidsFixture.adult),
        throwsA(isA<ProviderException>()),
      );
      expect(
        (await provider.resolvePlayback(KidsFixture.safe)).uri.scheme,
        'https',
      );
      final restored = CategoryLocks('kids');
      await restored.load();
      expect(restored.kidsProfile, isTrue);
      expect(restored.allowedKidsCategories, {'live:7'});
      await restored.setProfilePolicy(
        kids: true,
        requirePin: false,
        allowed: {},
      );
      expect(restored.allowsItem(KidsFixture.safe), isFalse);
      provider.dispose();
    },
  );
  test(
    'startup chooser defaults on, opt-out auto-selects last profile, PIN-protected profile never auto-opens',
    () async {
      const store = CredentialStore();
      final first = Session(registry(), store);
      await first.initialize();
      expect(first.showProfileSelectionOnStartup, isTrue);
      await first.connect(config('one'), name: 'One');
      await first.connect(config('two'), name: 'Two');
      final id = first.activeProfile!.id;
      await first.setShowProfileSelection(false);
      first.dispose();
      final second = Session(registry(), store);
      await second.initialize();
      expect(second.activeProfile!.id, id);
      expect(second.account, isNotNull);
      second.dispose();
      await CategoryLocks(id).setProfilePolicy(
        kids: false,
        requirePin: true,
        allowed: {},
        pin: '123456',
      );
      final third = Session(registry(), store);
      await third.initialize();
      expect(third.account, isNull);
      expect(third.lastProfileId, id);
      third.dispose();
    },
  );
}
