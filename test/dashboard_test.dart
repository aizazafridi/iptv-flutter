import 'package:iptv_flutter/presentation/weather_panel.dart';
import 'package:iptv_flutter/presentation/on_now_panel.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'tv_guide_screen_test.dart' show GuideProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  testWidgets(
    'dashboard shows On now programmes and immediately receives new watch history',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      final provider = GuideProvider();
      await MyList.forProvider(provider).toggle(
        const ContentItem(
          id: '1',
          name: 'Channel Alpha',
          type: ContentType.live,
        ),
      );
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: HomeScreen(session: session, appearance: AppAppearance()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Programme 1'), findsNWidgets(2));
      expect(find.text('Current weather'), findsOneWidget);
      final history = WatchHistory.forProvider(provider);
      await history.save(
        WatchEntry(
          const ContentItem(
            id: '42',
            name: 'Just started movie',
            type: ContentType.movies,
          ),
          null,
          const Duration(seconds: 2),
          const Duration(minutes: 90),
          DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Just started movie'), findsOneWidget);
      final parental = CategoryLocks.forProvider(provider);
      await parental.setPassword('123456');
      const protected = ContentItem(
        id: '42',
        name: 'Just started movie',
        type: ContentType.movies,
      );
      await parental.configureTitle(protected, true);
      parental.unlockTitle(protected, '123456');
      await tester.pumpAndSettle();
      expect(find.text('Just started movie'), findsNothing);
      await parental.configureTitle(protected, false);
      await tester.pumpAndSettle();
      expect(find.text('Just started movie'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('dashboard fits TV layout and opens Movies from navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    final session = Session(ProviderRegistry(), const CredentialStore())
      ..provider = FakeProvider()
      ..account = const Account('demo', 'Active', null)
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HomeScreen(session: session, appearance: AppAppearance()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current weather'), findsOneWidget);
    expect(find.text('On now'), findsOneWidget);
    final weatherRect = tester.getRect(find.byType(WeatherPanel));
    final nowRect = tester.getRect(find.byType(OnNowPanel));
    expect(weatherRect.left, greaterThan(nowRect.right));
    expect(weatherRect.top, closeTo(nowRect.top, 1));
    expect(find.text('Search channels, movies, series'), findsOneWidget);
    expect(find.text('Continue watching'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
