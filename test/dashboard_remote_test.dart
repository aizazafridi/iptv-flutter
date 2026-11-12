import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/data/last_live_channel.dart';
import 'package:flutter/material.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'tv_guide_screen_test.dart' show GuideProvider;

void main() {
  testWidgets(
    'Fire TV starts at Home and follows sidebar to Live TV to On Now',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = GuideProvider();
      await LastLiveChannel.forProvider(provider).save(
        const ContentItem(
          id: '1',
          name: 'Channel Alpha',
          type: ContentType.live,
        ),
      );
      await WatchHistory.forProvider(provider).save(
        WatchEntry(
          const ContentItem(
            id: 'movie',
            name: 'Continue movie',
            type: ContentType.movies,
          ),
          null,
          const Duration(minutes: 10),
          const Duration(minutes: 90),
          DateTime.now(),
        ),
      );
      final appearance = AppAppearance();
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Home',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        172,
      );
      final sidebar = find.byKey(const ValueKey('dashboard-sidebar'));
      expect(
        find.descendant(of: sidebar, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        find.descendant(of: sidebar, matching: find.text('Home')),
        findsOneWidget,
      );
      final sidebarRect = tester.getRect(sidebar);
      final buttons = find.descendant(
        of: sidebar,
        matching: find.byType(TextButton),
      );
      for (final element in buttons.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(rect.top, greaterThanOrEqualTo(sidebarRect.top));
        expect(rect.bottom, lessThanOrEqualTo(sidebarRect.bottom));
      }
      final continueTitle = find.text('Continue movie');
      expect(tester.getBottomRight(continueTitle).dy, lessThanOrEqualTo(540));
      Focus.of(tester.element(continueTitle)).requestFocus();
      await tester.pumpAndSettle();
      final dashboardScroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const PageStorageKey('dashboard-scroll')),
          )
          .controller!;
      expect(dashboardScroll.offset, 0);
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        172,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Live TV',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        172,
      );
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Live TV',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Movies',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Live TV',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard On Now',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Search',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        Focus.of(
          tester.element(find.byIcon(Icons.switch_account_outlined)),
        ).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        Focus.of(tester.element(find.byIcon(Icons.settings_outlined))).hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Search',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard On Now',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(BrowseScreen), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Live TV',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Movies',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(SeriesCatalogScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Home',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
  testWidgets('dashboard requires two Back presses before exiting', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final session = Session(ProviderRegistry(), const CredentialStore())
      ..provider = GuideProvider()
      ..account = const Account('demo', 'Active', null)
      ..loading = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(session: session, appearance: AppAppearance()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 0);
    expect(find.text('Press Back again to exit'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
