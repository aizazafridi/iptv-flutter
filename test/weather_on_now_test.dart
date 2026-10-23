import 'package:iptv_flutter/presentation/weather_scene_painter.dart';
import 'package:iptv_flutter/presentation/raincoat_weather_painter.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/data/weather_service.dart';
import 'package:iptv_flutter/presentation/weather_panel.dart';
import 'package:iptv_flutter/presentation/on_now_panel.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'tv_guide_screen_test.dart' show GuideProvider;

WeatherService fixture() => WeatherService(
  fetch: (uri) async => uri.host == 'ipwho.is'
      ? {
          'success': true,
          'city': 'Sample city',
          'latitude': 47.56,
          'longitude': -52.71,
        }
      : {
          'current': {
            'temperature_2m': 12.4,
            'apparent_temperature': 10.1,
            'wind_speed_10m': 15.0,
            'relative_humidity_2m': 72,
            'weather_code': 3,
            'time': 1792600000,
          },
        },
);
void main() {
  testWidgets('weather character animation advances', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: WeatherPanel(service: fixture())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final scene = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is WeatherScenePainter,
    );
    expect(scene, findsOneWidget);
    final before =
        (tester.widget<CustomPaint>(scene).painter! as WeatherScenePainter)
            .phase;
    await tester.pump(const Duration(milliseconds: 500));
    final after =
        (tester.widget<CustomPaint>(scene).painter! as WeatherScenePainter)
            .phase;
    expect(after, greaterThan(before));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rainy weather draws raincoat and umbrella scene', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final service = WeatherService(
      fetch: (uri) async {
        final data = await fixture().get(uri);
        if (data['current'] != null)
          (data['current'] as Map<String, dynamic>)['weather_code'] = 61;
        return data;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: WeatherPanel(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rain'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is RaincoatWeatherPainter,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Live TV browsing no longer contains On now', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: BrowseScreen(provider: GuideProvider(), type: ContentType.live),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On now'), findsNothing);
    expect(find.byType(OnNowPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'weather uses approved destinations and forwards approximate coordinates',
    () async {
      final requests = <Uri>[];
      final service = WeatherService(
        fetch: (uri) async {
          requests.add(uri);
          return fixture().get(uri);
        },
      );
      final result = await service.load();
      expect(result.city, 'Sample city');
      expect(result.condition, 'Overcast');
      expect(result.temperature, 12.4);
      expect(requests.map((u) => u.host), ['ipwho.is', 'api.open-meteo.com']);
      expect(requests.last.queryParameters['latitude'], '47.56');
    },
  );
  testWidgets(
    'weather replaces dashboard panel and On now renders channel programming',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 300, child: WeatherPanel(service: fixture())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample city'), findsOneWidget);
      expect(find.text('Overcast'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final provider = GuideProvider();
      await MyList.forProvider(provider).toggle(
        const ContentItem(
          id: '1',
          name: 'Channel Alpha',
          type: ContentType.live,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: OnNowPanel(provider: provider, onOpen: (_) async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Channel Alpha'), findsOneWidget);
      expect(find.text('Programme 1'), findsOneWidget);
      expect(
        tester.getRect(find.text('Programme 1')).left,
        greaterThan(tester.getRect(find.text('Channel Alpha')).right),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
