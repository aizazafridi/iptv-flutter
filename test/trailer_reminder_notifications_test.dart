import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/presentation/dashboard.dart';
import 'package:iptv_flutter/presentation/trailers_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/trailer_reminders.dart';
import 'package:iptv_flutter/application/recent_catalog_cache.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/domain/trailer_movie.dart';
import 'widget_test.dart' show FakeProvider;
import 'trailers_repository_test.dart' show fixtureRepo;

class ReminderProvider extends FakeProvider {
  int? detailId;
  String cast = '';
  List<ContentItem> catalog = [];
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async {
    catalogCalls++;
    return catalog;
  }

  @override
  Future<MediaDetails> getMovieDetails(ContentItem item) async {
    detailCalls++;
    return MediaDetails(item: item, synopsis: '', tmdbId: detailId, cast: cast);
  }
}

const movie = TrailerMovie(
  id: 77,
  title: 'Example',
  releaseDate: '2026-11-11',
  cast: [TrailerCastMember(name: 'Jane Actor')],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'dashboard shows notification inbox and keeps sidebar with Trailers',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = ReminderProvider();
      final reminders = TrailerReminders.forProvider(provider);
      await reminders.toggle(movie);
      await reminders.setPreferences(movie.id, release: false, availability: true);
      await reminders.checkCatalog(provider, [
        const ContentItem(
          id: 'one',
          name: 'Example',
          type: ContentType.movies,
          tmdbId: 77,
        ),
      ]);
      final session = Session(ProviderRegistry(), const CredentialStore())
        ..provider = provider
        ..account = const Account('demo', 'Active', null)
        ..loading = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StreamoraDashboard(
              trailersRepository: fixtureRepo(),
              session: session,
              appearance: AppAppearance(),
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('dashboard-search')),
          )
          .focusNode!
          .requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard Notifications',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.text('Example is now available in your library.'),
        findsOneWidget,
      );
      expect(find.text('View Movie Details'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(reminders.unread, 0);
      final nav = find.byWidgetPredicate(
        (w) =>
            w is TextButton &&
            w.focusNode?.debugLabel == 'dashboard nav Trailers',
      );
      await tester.ensureVisible(nav);
      await tester.tap(nav);
      await tester.pumpAndSettle();
      expect(find.byType(TrailersScreen), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('dashboard-sidebar'))).width,
        76,
      );
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Trailers',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'dashboard nav Home',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  test('release notices persist once per event and isolate profiles', () async {
    var now = DateTime(2026, 11, 10);
    final reminders = TrailerReminders('one', clock: () => now);
    await reminders.toggle(movie);
    await reminders.checkDates();
    expect(reminders.notices, isEmpty);
    now = DateTime(2026, 11, 11);
    await reminders.checkDates();
    expect(reminders.unread, 1);
    await reminders.markRead();
    final restarted = TrailerReminders('one', clock: () => now);
    await restarted.checkDates();
    expect(restarted.items.single.id, 77);
    expect(restarted.notices.length, 1);
    expect(restarted.unread, 0);
    final other = TrailerReminders('two', clock: () => now);
    await other.checkDates();
    expect(other.items, isEmpty);
    expect(other.notices, isEmpty);
  });
  test('preferences persist and removed reminders stop events', () async {
    var now = DateTime(2026, 11, 10);
    final reminders = TrailerReminders('prefs', clock: () => now);
    await reminders.toggle(movie);
    await reminders.setPreferences(77, release: false, availability: false);
    now = DateTime(2026, 11, 12);
    final restarted = TrailerReminders('prefs', clock: () => now);
    await restarted.checkDates();
    final provider = ReminderProvider();
    await restarted.checkCatalog(provider, [
      const ContentItem(
        id: 'p',
        name: 'Example',
        type: ContentType.movies,
        tmdbId: 77,
      ),
    ]);
    expect(restarted.notices, isEmpty);
    expect(restarted.preferences(77).availability, false);
    await restarted.toggle(movie);
    await restarted.checkDates();
    expect(restarted.items, isEmpty);
    expect(restarted.notices, isEmpty);
  });
  test(
    'TMDB ID matches without title/year guessing and notifications deduplicate',
    () async {
      final provider = ReminderProvider();
      final reminders = TrailerReminders('id');
      await reminders.toggle(movie);
      final catalog = [
        const ContentItem(
          id: 'p',
          name: 'Localized title',
          type: ContentType.movies,
          tmdbId: 77,
        ),
      ];
      await reminders.checkCatalog(provider, catalog);
      await reminders.checkCatalog(provider, catalog);
      expect(
        reminders.notices.single.message,
        'Example is now available in your library.',
      );
      expect(provider.detailCalls, 0);
      final restarted = TrailerReminders('id');
      await restarted.checkCatalog(provider, catalog);
      expect(restarted.notices.length, 1);
    },
  );
  test(
    'title/year fallback requires corroboration and rejects conflicting IDs',
    () async {
      final provider = ReminderProvider();
      final reminders = TrailerReminders('matching');
      await reminders.toggle(movie);
      const item = ContentItem(
        id: 'p',
        name: 'Example (2026) (Hindi) (4K)',
        type: ContentType.movies,
        releaseYear: 2026,
      );
      await reminders.checkCatalog(provider, [item]);
      expect(reminders.notices, isEmpty);
      provider.detailId = 999;
      provider.cast = 'Jane Actor';
      await reminders.checkCatalog(provider, [item]);
      expect(reminders.notices, isEmpty);
      provider.detailId = null;
      await reminders.checkCatalog(provider, [
        const ContentItem(
          id: 'old',
          name: 'Example',
          type: ContentType.movies,
          releaseYear: 2025,
        ),
      ]);
      expect(reminders.notices, isEmpty);
      await reminders.checkCatalog(provider, [item]);
      expect(reminders.notices.length, 1);
    },
  );
  test(
    'catalog refresh reuses fetched items and never downloads another playlist',
    () async {
      final provider = ReminderProvider()
        ..catalog = [
          const ContentItem(
            id: 'p',
            name: 'Example',
            type: ContentType.movies,
            tmdbId: 77,
          ),
        ];
      final reminders = TrailerReminders.forProvider(provider);
      await reminders.toggle(movie);
      await RecentCatalogCache.loadAll(provider, ContentType.movies);
      for (var i = 0; i < 30 && reminders.notices.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(reminders.notices.length, 1);
      await RecentCatalogCache.loadAll(provider, ContentType.movies);
      expect(provider.catalogCalls, 1);
      RecentCatalogCache.invalidate(provider);
      await RecentCatalogCache.loadAll(provider, ContentType.movies);
      expect(provider.catalogCalls, 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reminders.notices.length, 1);
    },
  );
}
