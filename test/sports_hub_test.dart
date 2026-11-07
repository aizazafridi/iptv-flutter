import 'package:iptv_flutter/application/live_score_service.dart';
import 'package:iptv_flutter/domain/live_score.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/application/sports_favorites.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/domain/sports.dart';
import 'package:iptv_flutter/presentation/sports_hub_screen.dart';
import 'package:iptv_flutter/presentation/shared_artwork_image.dart';
import 'widget_test.dart' show FakeProvider;

class SportsFixtureApi implements SportsDataProvider {
  int liveCalls = 0, dayCalls = 0, upcomingCalls = 0;
  String? queriedSport;
  final dates = <DateTime>[];
  bool fail = false, omitCricket = false;
  SportsEvent get event => SportsEvent(
    id: 'e1',
    name: 'Arsenal vs Chelsea',
    sportId: 'Soccer',
    leagueId: '4328',
    leagueName: 'Premier League',
    homeTeamId: '1',
    awayTeamId: '2',
    homeTeamName: 'Arsenal',
    awayTeamName: 'Chelsea',
    startTimeUtc: DateTime.now().toUtc().add(const Duration(minutes: 2)),
    homeTeamLogo: 'https://images.example.com/a.png',
    status: SportsEventStatus.scheduled,
  );
  @override
  bool get limitedCoverage => true;
  @override
  bool get supportsLive => false;
  @override
  String get attribution => 'Sports data: TheSportsDB';
  @override
  Future<List<Sport>> getSports() async => [
    const Sport('102', 'Soccer'),
    if (!omitCricket) const Sport('103', 'Cricket'),
  ];
  @override
  Future<List<SportsLeague>> getLeagues() async => [
    const SportsLeague('4328', 'Premier League', sportId: 'Soccer'),
  ];
  @override
  Future<List<SportsEvent>> getEventsByDate(
    DateTime date, {
    String? sport,
  }) async {
    dates.add(date);
    dayCalls++;
    queriedSport = sport;
    if (fail) {
      throw const SportsDataException('Unable to update sports information.');
    }
    return [event];
  }

  @override
  Future<List<SportsEvent>> getUpcomingEvents({
    String? leagueId,
    String? teamId,
  }) async {
    upcomingCalls++;
    return [event];
  }

  @override
  Future<List<SportsEvent>> getRecentResults({
    String? leagueId,
    String? teamId,
  }) async => [];
  @override
  Future<SportsEvent?> getEventDetails(String id) async => event;
  @override
  Future<List<SportsTeam>> getTeams(String query) async => [
    const SportsTeam('1', 'Arsenal'),
  ];
  @override
  Future<SportsTeam?> getTeamDetails(String id) async =>
      const SportsTeam('1', 'Arsenal');
  @override
  Future<SportsLeague?> getLeagueDetails(String id) async =>
      const SportsLeague('4328', 'Premier League');
  @override
  Future<List<SportsEvent>> getLiveScores() async {
    liveCalls++;
    return [];
  }

  @override
  void dispose() {}
}

class GridSportsApi extends SportsFixtureApi {
  @override
  Future<List<SportsEvent>> getEventsByDate(
    DateTime date, {
    String? sport,
  }) async => [
    event,
    SportsEvent(
      id: 'e2',
      name: 'Second fixture',
      startTimeUtc: event.startTimeUtc,
    ),
  ];
}

class WidgetScoreProvider implements LiveScoreProvider {
  String homeScore = '2';
  @override
  String get providerId => 'fixture-scores';
  @override
  Duration get refreshInterval => const Duration(minutes: 2);
  @override
  String? get error => null;
  @override
  int get requestCount => 0;
  @override
  DateTime? get lastSuccess => null;
  @override
  Future<List<LiveScoreEvent>> getLiveEvents() async => [
    LiveScoreEvent(
      providerId: providerId,
      providerEventId: 'external-1',
      sport: 'Soccer',
      leagueName: 'Premier League',
      homeTeamName: 'Arsenal',
      awayTeamName: 'Chelsea',
      startTimeUtc: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      fetchedAt: DateTime.now().toUtc(),
      freshUntil: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      status: SportsEventStatus.live,
      homeScore: homeScore,
      awayScore: '1',
    ),
  ];
  @override
  Future<LiveScoreEvent?> getEventScore(SportsEvent event) async => null;
  @override
  void dispose() {}
}

class SportsPlaylist extends FakeProvider {
  final int count;
  SportsPlaylist({this.count = 1});
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    for (var i = 0; i < count; i++)
      ContentItem(
        id: i == 0 ? 'espn-42' : 'espn-$i',
        name: i == 0 ? 'US: ESPN 1 HD' : 'Sports Channel $i',
        type: ContentType.live,
      ),
  ];
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    BrowsingModeSettings.instance.mode = BrowsingMode.lite;
  });
  tearDown(() => BrowsingModeSettings.instance.mode = BrowsingMode.premium);
  Future<void> mount(
    WidgetTester tester,
    SportsFixtureApi api, {
    Future<void> Function(ContentItem)? onWatch,
    int channelCount = 1,
    LiveScoreService? scoreService,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SportsHubScreen(
          provider: SportsPlaylist(count: channelCount),
          sportsProvider: api,
          liveScores: scoreService,
          onWatch: onWatch ?? (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'score updates preserve fixture ID and focus; details show source',
    (tester) async {
      final api = SportsFixtureApi();
      final scores = WidgetScoreProvider();
      final service = LiveScoreService(
        api,
        config: const LiveScoreConfig(mode: 'development_multi_api'),
        providers: [scores],
      );
      await mount(tester, api, scoreService: service);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      final card = tester.widget<SportsEventCard>(find.byType(SportsEventCard));
      expect(card.event.id, 'e1');
      card.focusNode.requestFocus();
      await tester.pumpAndSettle();
      scores.homeScore = '3';
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Refresh',
            ),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(card.focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining('3 - 1'), findsOneWidget);
      expect(find.textContaining('fixture-scores'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(card.focusNode.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    },
  );
  testWidgets('sports hub and details omit generic sports channel lists', (
    tester,
  ) async {
    await mount(tester, SportsFixtureApi(), channelCount: 16);
    expect(find.text('Your Sports Channels'), findsNothing);
    expect(find.text('US: ESPN 1 HD'), findsNothing);
    await tester.tap(find.text('Match Details'));
    await tester.pumpAndSettle();
    expect(find.text('Browse Sports Channels'), findsNothing);
    expect(find.text('US: ESPN 1 HD'), findsNothing);
    expect(find.text('Find Channels'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('cards share a two-column row on TV and stack on small windows', (
    tester,
  ) async {
    await mount(tester, GridSportsApi());
    final first = find.byKey(const ValueKey('e1'));
    final second = find.byKey(const ValueKey('e2'));
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(
      tester.getTopLeft(second).dx,
      greaterThan(tester.getTopLeft(first).dx),
    );
    final node = tester.widget<SportsEventCard>(first).focusNode;
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<SportsEventCard>(second).focusNode.hasFocus, isTrue);
    tester.view.physicalSize = const Size(600, 1000);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
    expect(
      tester.getTopLeft(second).dy,
      greaterThan(tester.getTopLeft(first).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('D-pad moves between sport filters and sections', (tester) async {
    await mount(tester, SportsFixtureApi());
    Focus.of(tester.element(find.text('All'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Cricket'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Football'))).hasFocus, isTrue);
    final before = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(FocusManager.instance.primaryFocus, isNot(same(before)));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Cricket stays available when free sports list omits it', (
    tester,
  ) async {
    final api = SportsFixtureApi()..omitCricket = true;
    await mount(tester, api);
    expect(find.text('Cricket'), findsOneWidget);
    await tester.tap(find.text('Cricket'));
    await tester.pumpAndSettle();
    expect(api.queriedSport, 'Cricket');
    expect(find.text('No matches available for this date.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('real models render and football uses Soccer provider filter', (
    tester,
  ) async {
    final api = SportsFixtureApi();
    await mount(tester, api);
    expect(find.text('Sports Hub'), findsOneWidget);
    expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
    await tester.tap(find.text('Football'));
    await tester.pumpAndSettle();
    expect(api.queriedSport, 'Soccer');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('live honestly unavailable and no feed request', (tester) async {
    final api = SportsFixtureApi();
    await mount(tester, api);
    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Live scores are not available with the current sports data plan.',
      ),
      findsOneWidget,
    );
    // The capability is checked by UI; adapter also guarantees no HTTP requests.
    expect(find.textContaining('2 - 1'), findsNothing);
    expect(api.liveCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('details opens using remote OK and Back restores card focus', (
    tester,
  ) async {
    await mount(tester, SportsFixtureApi());
    final card = tester.widget<SportsEventCard>(find.byType(SportsEventCard));
    card.focusNode.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(SportsEventDetailsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(card.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Lite hub/details omit artwork; Premium hub/details use shared artwork',
    (tester) async {
      await mount(tester, SportsFixtureApi());
      expect(find.byType(SharedArtworkImage), findsNothing);
      await tester.tap(find.text('Match Details'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedArtworkImage), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await BrowsingModeSettings.instance.choose(BrowsingMode.premium);
      await tester.pumpAndSettle();
      expect(find.byType(SharedArtworkImage), findsWidgets);
      await tester.tap(find.text('Match Details'));
      await tester.pumpAndSettle();
      expect(find.byType(SharedArtworkImage), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('refresh preserves event focus node', (tester) async {
    await mount(tester, SportsFixtureApi());
    final node = tester
        .widget<SportsEventCard>(find.byType(SportsEventCard))
        .focusNode;
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(
      identical(
        node,
        tester.widget<SportsEventCard>(find.byType(SportsEventCard)).focusNode,
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('fixture failure does not expose a generic channel list', (
    tester,
  ) async {
    final api = SportsFixtureApi()..fail = true;
    ContentItem? launched;
    await mount(
      tester,
      api,
      onWatch: (item) async {
        launched = item;
      },
    );
    expect(find.text('Unable to update sports information.'), findsOneWidget);
    expect(find.text('Your Sports Channels'), findsNothing);
    expect(find.text('US: ESPN 1 HD'), findsNothing);
    expect(launched, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'follow teams and leagues from details persists then My Teams works',
    (tester) async {
      final api = SportsFixtureApi();
      await mount(tester, api);
      await tester.tap(find.text('Match Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow Arsenal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Follow League'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Teams'));
      await tester.pumpAndSettle();
      expect(api.upcomingCalls, greaterThan(0));
      final favorites = SportsFavorites(
        WatchHistory.forProvider(
          tester.widget<SportsHubScreen>(find.byType(SportsHubScreen)).provider,
        ).scope,
      );
      await favorites.load();
      expect(favorites.teams['1'], 'Arsenal');
      expect(favorites.leagues['4328'], 'Premier League');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Upcoming and Results tabs change data source', (tester) async {
    final api = SportsFixtureApi();
    await mount(tester, api);
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    final localTomorrow = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day + 1,
    ).toUtc();
    expect(
      api.dates.any(
        (d) =>
            d.year == localTomorrow.year &&
            d.month == localTomorrow.month &&
            d.day == localTomorrow.day,
      ),
      isTrue,
    );
    await tester.tap(find.text('Results'));
    await tester.pumpAndSettle();
    expect(find.text('No matches available for this date.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
