import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/data/locked_provider.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/settings_screen.dart';
import 'package:iptv_flutter/presentation/title_lock_settings_screen.dart';
import 'package:iptv_flutter/presentation/category_lock_settings_screen.dart';
import 'profiles_locks_test.dart' show CatalogFixture, registry, config;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('PIN requires six ASCII digits and preserves leading zeroes', () async {
    final locks = CategoryLocks('six');
    for (final invalid in [
      '1234',
      '12345',
      '1234567',
      'abcdef',
      '12 456',
      '??????',
    ]) {
      await expectLater(
        locks.setPassword(invalid),
        throwsA(isA<ProviderException>()),
      );
    }
    await locks.setPassword('001029');
    final restored = CategoryLocks('six');
    await restored.load();
    expect(restored.check('001029'), isTrue);
    expect(restored.check('1029'), isFalse);
  });
  test(
    'hidden title persists per profile and is blocked in lists, search and direct playback',
    () async {
      final locks = CategoryLocks('alice');
      const item = ContentItem(
        id: '42',
        name: 'Title',
        type: ContentType.movies,
        categoryId: '7',
      );
      await locks.setTitleHidden(item, true);
      final restored = CategoryLocks('alice');
      await restored.load();
      final provider = LockedProvider(CatalogFixture(), restored);
      expect(
        (await provider.getItems(const Category('7', '', ContentType.movies))),
        isEmpty,
      );
      expect(
        (await provider.getAllItems(ContentType.movies)).map((row) => row.id),
        ['88'],
      );
      expect((await provider.visibleSavedItems([item])), isEmpty);
      await expectLater(
        provider.resolvePlayback(item),
        throwsA(isA<ProviderException>()),
      );
      final other = CategoryLocks('bob');
      await other.load();
      expect(other.titleHidden(item), isFalse);
      await restored.setTitleHidden(item, false);
      expect(
        (await provider.getItems(const Category('7', '', ContentType.movies))),
        hasLength(1),
      );
      provider.dispose();
    },
  );
  test(
    'existing short PIN can authenticate for upgrade without losing flags',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'category_locks:legacy': jsonEncode({
          'password': '1234',
          'categories': ['movies:7'],
          'titles': ['movies:42'],
          'hidden': ['series:9'],
        }),
      });
      final locks = CategoryLocks('legacy');
      await locks.load();
      expect(locks.check('1234'), isTrue);
      expect(locks.needsPinUpgrade, isTrue);
      await locks.setPassword('012345', current: '1234');
      expect(locks.needsPinUpgrade, isFalse);
      expect(
        locks.configured(const Category('7', '', ContentType.movies)),
        isTrue,
      );
      expect(locks.hidden(const Category('9', '', ContentType.series)), isTrue);
    },
  );
  testWidgets('parental settings require the profile PIN on each entry', (
    tester,
  ) async {
    final session = Session(registry(), const CredentialStore());
    await session.connect(config('gate'));
    final locks = CategoryLocks.forProvider(session.provider!);
    await locks.setPassword('123456');
    final appearance = AppAppearance();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          session: session,
          appearance: appearance,
          switchUser: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parental controls'));
    await tester.pumpAndSettle();
    expect(find.text('Enter parental PIN'), findsOneWidget);
    expect(find.text('Set or change parental PIN'), findsNothing);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Set or change parental PIN'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parental controls'));
    await tester.pumpAndSettle();
    expect(find.text('Enter parental PIN'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    appearance.dispose();
  });
  testWidgets(
    'category filters display persisted protected and hidden categories',
    (tester) async {
      final provider = CatalogFixture();
      final saved = CategoryLocks('category-filter');
      await saved.setPassword('123456');
      await saved.configureCategory(
        const Category('7', '', ContentType.movies),
        true,
      );
      await saved.setHidden(const Category('9', '', ContentType.movies), true);
      final locks = CategoryLocks('category-filter');
      CategoryLocks.attach(provider, locks);
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryLockSettingsScreen(
            provider: provider,
            type: ContentType.movies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PIN protected (1)'), findsOneWidget);
      expect(find.text('Hidden (1)'), findsOneWidget);
      await tester.tap(find.text('PIN protected (1)'));
      await tester.pumpAndSettle();
      expect(find.text('English (4K)'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.tap(find.text('Hidden (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('English (4K)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'title panel shows persisted hidden and PIN protected entries with separate toggles',
    (tester) async {
      final provider = CatalogFixture();
      final locks = CategoryLocks('filter');
      CategoryLocks.attach(provider, locks);
      await locks.setPassword('123456');
      const item = ContentItem(
        id: '42',
        name: 'Title',
        type: ContentType.movies,
      );
      await locks.configureTitle(item, true);
      await locks.setTitleHidden(item, true);
      await tester.pumpWidget(
        MaterialApp(
          home: TitleLockSettingsScreen(
            provider: provider,
            type: ContentType.movies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hidden (1)'), findsOneWidget);
      expect(find.text('PIN protected (1)'), findsOneWidget);
      await tester.tap(find.text('Hidden (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Locked title'), findsOneWidget);
      expect(find.text('Open title'), findsNothing);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.length, 2);
      expect(switches.every((control) => control.value), isTrue);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
