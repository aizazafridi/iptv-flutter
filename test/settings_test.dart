import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'background color persists independently of account credentials',
    () async {
      final appearance = AppAppearance();
      await appearance.choose('Forest');
      final reloaded = AppAppearance();
      await reloaded.load();
      expect(reloaded.selected, 'Forest');
      expect(reloaded.brightness, Brightness.dark);
      await reloaded.choose('Light');
      expect(reloaded.brightness, Brightness.light);
      appearance.dispose();
      reloaded.dispose();
    },
  );

  testWidgets(
    'centered home opens settings and switches to fresh credentials',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final registry = ProviderRegistry();
      registry.register('fixture', 'Fixture', (_) => FakeProvider());
      const store = CredentialStore();
      final session = Session(registry, store);
      final appearance = AppAppearance();
      await session.connect(
        const ProviderConfig(
          providerId: 'fixture',
          server: 'https://example.com',
          username: 'old-user',
          password: 'old-password',
        ),
      );
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: appearance,
          builder: (_, _) => MaterialApp(
            theme: ThemeData(
              brightness: appearance.brightness,
              scaffoldBackgroundColor: appearance.background,
            ),
            home: HomeScreen(session: session, appearance: appearance),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Movies')).dx, closeTo(550, 1));
      expect(
        tester.getCenter(find.byTooltip('Settings')).dx,
        greaterThan(1000),
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final history = WatchHistory.forProvider(session.provider!);
      await history.save(
        WatchEntry(
          const ContentItem(id: '42', name: 'Movie', type: ContentType.movies),
          null,
          const Duration(minutes: 2),
          const Duration(minutes: 10),
          DateTime.utc(2026),
        ),
      );
      await tester.tap(find.text('Clear watch history'));
      await tester.pumpAndSettle();
      expect(find.text('Movies only'), findsOneWidget);
      expect(find.text('Series only'), findsOneWidget);
      await tester.tap(find.text('All watch history'));
      await tester.pumpAndSettle();
      expect(await history.entries(), isEmpty);
      expect(
        find.text('Watch history cleared for this account.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Navy'));
      await tester.pumpAndSettle();
      expect(appearance.selected, 'Navy');
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor,
        isNull,
      );
      expect(
        Theme.of(
          tester.element(find.text('App background color')),
        ).scaffoldBackgroundColor,
        AppAppearance.backgrounds['Navy'],
      );
      await tester.tap(find.text('Switch account'));
      await tester.pumpAndSettle();
      expect(session.account, isNull);
      expect(session.provider, isNull);
      expect(await store.load(), isNull);
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(session.profiles.length, 1);
      expect((await store.loadProfiles())!.length, 1);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      expect(find.text('Connect'), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[1].controller!.text, 'https://example.com');
      expect(fields[3].controller!.text, isEmpty);
      expect(fields[2].controller!.text, isEmpty);
      expect(appearance.selected, 'Midnight');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
