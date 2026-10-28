import 'package:iptv_flutter/data/last_live_channel.dart';
import 'package:iptv_flutter/presentation/weather_panel.dart';
import 'package:iptv_flutter/presentation/on_now_panel.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/watch_history.dart';
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
      await LastLiveChannel.forProvider(provider).save(
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
      expect(
        tester.widget<WeatherPanel>(find.byType(WeatherPanel)).compact,
        isTrue,
      );
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
      const series = ContentItem(
        id: 'show',
        name: 'Unfinished series',
        type: ContentType.series,
      );
      for (final number in [1, 2]) {
        await history.save(
          WatchEntry(
            series,
            Episode(
              id: 'episode$number',
              title: 'Episode $number',
              season: 1,
              number: number,
              extension: 'mp4',
            ),
            const Duration(minutes: 10),
            const Duration(minutes: 40),
            DateTime.now().add(Duration(seconds: number)),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Unfinished series'), findsOneWidget);
      expect(find.textContaining('S1 E2'), findsOneWidget);
      expect(find.textContaining('S1 E1'), findsNothing);
      expect(
        (await history.entries()).where((entry) => entry.item.id == 'show'),
        hasLength(2),
      );
      expect(
        (await history.latest(
          series,
          episode: const Episode(
            id: 'episode1',
            title: 'Episode 1',
            season: 1,
            number: 1,
            extension: 'mp4',
          ),
        ))?.position,
        const Duration(minutes: 10),
      );
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
      final movie = find.text('Just started movie');
      final focused = Focus.of(tester.element(movie));
      focused.requestFocus();
      await tester.pumpAndSettle();
      expect(find.text('S'), findsOneWidget);
      await tester.ensureVisible(movie);
      await tester.tap(movie);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(focused.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
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
    expect(
      tester.widget<WeatherPanel>(find.byType(WeatherPanel)).compact,
      isTrue,
    );
    expect(find.text('On now'), findsOneWidget);
    final weatherRect = tester.getRect(find.byType(WeatherPanel));
    final nowRect = tester.getRect(find.byType(OnNowPanel));
    expect(weatherRect.bottom, lessThan(nowRect.top));
    expect(weatherRect.height, lessThanOrEqualTo(48));
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Recently added ? Movies'), findsNothing);
    expect(find.text('Recently added ? Series'), findsNothing);
    expect(find.text('Continue watching'), findsOneWidget);
    const navigation = ['Home', 'Live TV', 'Movies', 'Series', 'TV Guide'];
    for (var i = 1; i < navigation.length; i++) {
      expect(
        tester.getTopLeft(find.byTooltip(navigation[i])).dy,
        greaterThan(tester.getTopLeft(find.byTooltip(navigation[i - 1])).dy),
      );
    }
    expect(find.byTooltip('Settings'), findsOneWidget);

    final feature = tester.getRect(
      find.byKey(const ValueKey('dashboard-live-feature')),
    );
    final onNow = tester.getRect(
      find.byKey(const ValueKey('dashboard-on-now')),
    );
    expect(feature.width / onNow.width, closeTo(1.5, .01));
    expect(onNow.left - feature.right, closeTo(18, .1));
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Recently Added Movies'), findsNothing);
    final artwork = tester.getSize(
      find.byKey(const ValueKey('dashboard-channel-artwork')),
    );
    expect(artwork.width, closeTo(artwork.height, .1));
    Focus.of(tester.element(find.text('Search'))).requestFocus();
    await tester.pumpAndSettle();
    final searchButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('dashboard-search')),
    );
    expect(
      searchButton.style!.backgroundColor!.resolve({WidgetState.focused}),
      const Color(0xff284f77),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Movies'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
