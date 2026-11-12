import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/trailers_screen.dart';
import 'package:iptv_flutter/presentation/shared_artwork_image.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/application/trailer_reminders.dart';
import 'package:iptv_flutter/data/trailers_repository.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'widget_test.dart' show FakeProvider;
import 'trailers_repository_test.dart' show fixtureRepo;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'Premium discovery fits $size, updates hero on focus, and opens details',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
        final repo = fixtureRepo();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: TrailersScreen(
              provider: FakeProvider(),
              repository: repo,
              reminders: TrailerReminders('ui'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Upcoming Hollywood Releases'), findsOneWidget);
        expect(find.text('Upcoming Hindi Releases'), findsNothing);
        expect(find.text('Watch Trailer'), findsNothing);
        expect(find.text('Remind Me'), findsNothing);
        expect(find.text('Details'), findsNothing);

        expect(tester.takeException(), isNull);
        final card = find.byType(TrailerDiscoveryCard).first;
        final button = find.descendant(
          of: card,
          matching: find.byType(TextButton),
        );
        (tester.widget<TextButton>(button).focusNode!).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(
          find.byKey(const ValueKey('trailers-hero-title')),
        );
        expect(title.data, 'Movie 12');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(TrailerMovieDetailsScreen), findsOneWidget);
        expect(
          tester.getSize(
            find.byKey(const ValueKey('trailer-cinematic-details')),
          ),
          size,
        );
        expect(find.text('Watch Trailer'), findsOneWidget);
        expect(find.text('Remind Me'), findsOneWidget);
        expect(find.text('More Info'), findsNothing);
        final synopsis = tester.widget<Text>(
          find.byKey(const ValueKey('trailer-details-synopsis')),
        );
        expect(
          synopsis.style?.fontSize,
          20 * (size.width / 1920).clamp(.62, 1.0),
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.context, isNotNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.text('Now in Theaters'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('Lite discovery has no artwork widgets and saves Remind Me', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await BrowsingModeSettings.instance.choose(BrowsingMode.lite);
    final reminders = TrailerReminders('lite');
    await tester.pumpWidget(
      MaterialApp(
        home: TrailersScreen(
          provider: FakeProvider(),
          repository: fixtureRepo(),
          reminders: reminders,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SharedArtworkImage), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(TrailerDiscoveryCard).first,
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SharedArtworkImage), findsNothing);
    await tester.tap(find.text('Remind Me').first);
    await tester.pumpAndSettle();
    expect(reminders.items, isNotEmpty);
    expect(find.text('Reminder Set'), findsOneWidget);
    await tester.tap(find.text('Reminder Set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Available in my library'));
    await tester.tap(find.text('Save Preferences'));
    await tester.pumpAndSettle();
    expect(reminders.preferences(reminders.items.first.id).availability, false);
    final restored = TrailerReminders('lite');
    await restored.load();
    expect(restored.preferences(restored.items.first.id).availability, false);
    await tester.tap(find.text('Reminder Set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Reminder'));
    await tester.pumpAndSettle();
    expect(reminders.items, isEmpty);
    expect(find.text('Remind Me'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
  });
  testWidgets('empty and missing trailer states stay usable', (tester) async {
    final repo = TrailersRepository(
      persist: false,
      client: TmdbCastService(
        fetch: (u) async => {'page': 1, 'total_pages': 1, 'results': []},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrailersScreen(
          provider: FakeProvider(),
          repository: repo,
          reminders: TrailerReminders('empty'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No movies available in this collection.'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('View All paginates without treating TMDB ids as IPTV ids', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrailerCollectionScreen(
          provider: FakeProvider(),
          collection: TrailerCollection.upcoming,
          repository: fixtureRepo(),
          reminders: TrailerReminders('pages'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TrailerDiscoveryCard), findsNWidgets(2));
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.byType(TrailerDiscoveryCard), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Kids profile cannot fetch discovery or initialize artwork', (
    tester,
  ) async {
    final provider = FakeProvider();
    final locks = CategoryLocks.forProvider(provider);
    await locks.setProfilePolicy(
      kids: true,
      requirePin: false,
      allowed: {},
      pin: '123456',
    );
    final requests = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TrailersScreen(
          provider: provider,
          repository: fixtureRepo(requests: requests),
          reminders: TrailerReminders('kids'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Trailers discovery is not available in Kids profiles.'),
      findsOneWidget,
    );
    expect(requests, isEmpty);
    expect(find.byType(SharedArtworkImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
