import 'package:iptv_flutter/presentation/player_screen.dart';
import 'guide_player_stability_test.dart' show StableEngine;
import 'live_tv_experience_test.dart' show alpha, source;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_favourite_groups.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/presentation/live_favourite_dialogs.dart';
import 'profiles_locks_test.dart' show CatalogFixture;
import 'live_favourite_groups_test.dart' show channels;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('player membership dialog keeps the stream and surface stable', (
    tester,
  ) async {
    final provider = CatalogFixture();
    final engine = StableEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(
          source: source(alpha),
          item: alpha,
          provider: provider,
          liveTvMode: true,
          engineFactory: () => engine,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final builds = engine.builds;
    await tester.tap(find.text('My List'));
    await tester.pumpAndSettle();
    expect(find.text('Add to My List'), findsOneWidget);
    await tester.tap(find.text('All Favorites'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(MyList.forProvider(provider).contains(alpha), isTrue);
    expect(engine.opens, 1);
    expect(engine.surfaces, 1);
    expect(engine.builds, builds);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
  for (final width in [1280.0, 1920.0]) {
    testWidgets('membership draft cancels and saves at $width', (tester) async {
      tester.view.physicalSize = Size(width, width * 9 / 16);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = CatalogFixture();
      final groups = LiveFavouriteGroups.forProvider(provider);
      final list = MyList.forProvider(provider);
      final a = await groups.create('Sports');
      final b = await groups.create('News');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showLiveFavouriteDialog(context, provider, channels.first),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sports'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(list.contains(channels.first), isFalse);
      expect(groups.memberships('1'), isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await tester.tap(find.text('Sports'));
      await tester.tap(find.text('News'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(list.contains(channels.first), isTrue);
      expect(groups.memberships('1'), {a, b});
      final restored = LiveFavouriteGroups(groups.scope);
      await restored.load();
      expect(restored.memberships('1'), {a, b});
      await list.toggle(channels.first);
      expect(groups.memberships('1'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    });
  }
  testWidgets(
    'creating group survives membership cancellation and rejects duplicates inline',
    (tester) async {
      final provider = CatalogFixture();
      final groups = LiveFavouriteGroups.forProvider(provider);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showLiveFavouriteDialog(context, provider, channels.first),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create New Group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' News ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create New Group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'news');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a different group name.'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(groups.groups.single.name, 'News');
      expect(groups.groups.single.channels, isEmpty);
      expect(MyList.forProvider(provider).contains(channels.first), isFalse);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
