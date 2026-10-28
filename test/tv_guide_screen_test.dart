import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/domain/iptv_provider.dart';
import 'package:iptv_flutter/presentation/tv_guide_screen.dart';
import 'widget_test.dart' show FakeProvider;

class GuideProvider extends FakeProvider implements EpgProvider {
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    const ContentItem(id: '1', name: 'Channel Alpha', type: ContentType.live),
    const ContentItem(id: '2', name: 'Channel Beta', type: ContentType.live),
  ];
  @override
  Future<List<EpgProgramme>> getEpg(ContentItem channel) async => [
    EpgProgramme(
      title: 'Programme ${channel.id}',
      description: 'Programme description',
      start: DateTime.now().subtract(const Duration(minutes: 10)),
      end: DateTime.now().add(const Duration(minutes: 20)),
    ),
  ];
}

class CategoryGuideProvider extends GuideProvider {
  @override
  Future<List<Category>> getCategories(ContentType type) async => [
    const Category('a', 'News', ContentType.live),
    for (var i = 0; i < 25; i++)
      Category('extra$i', 'Category $i', ContentType.live),
    const Category('b', 'Sports', ContentType.live),
  ];
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) async => [
    const ContentItem(
      id: '1',
      name: 'Channel Alpha',
      type: ContentType.live,
      categoryId: 'a',
    ),
    const ContentItem(
      id: '2',
      name: 'Channel Beta',
      type: ContentType.live,
      categoryId: 'b',
    ),
  ];
}

class DurationProvider extends GuideProvider {
  @override
  Future<List<EpgProgramme>> getEpg(ContentItem channel) async {
    final start = DateTime.now().toUtc().add(const Duration(hours: 1));
    return [
      EpgProgramme(
        title: 'Short',
        description: '',
        start: start,
        end: start.add(const Duration(minutes: 30)),
      ),
      EpgProgramme(
        title: 'Long',
        description: '',
        start: start.add(const Duration(minutes: 30)),
        end: start.add(const Duration(minutes: 120)),
      ),
    ];
  }
}

void main() {
  testWidgets(
    'guide filters current category and follows remote focus ladder',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TvGuideScreen(
            provider: CategoryGuideProvider(),
            previewChannel: const ContentItem(
              id: '2',
              name: 'Channel Beta',
              type: ContentType.live,
              categoryId: 'b',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-channel:1')), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'guide channel 2');
      for (final label in [
        'guide category b',
        'guide search',
        'guide refresh',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
      }
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      for (final label in [
        'guide search',
        'guide category b',
        'guide channel 2',
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, label);
      }
      tester
          .widgetList<ListView>(find.byType(ListView))
          .firstWhere((list) => list.scrollDirection == Axis.horizontal)
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-channel:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-channel:2')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'guide opens with the currently playing channel as its first row',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TvGuideScreen(
            provider: GuideProvider(),
            previewChannel: const ContentItem(
              id: '2',
              name: 'Channel Beta',
              type: ContentType.live,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final beta = tester.getTopLeft(
        find.byKey(const ValueKey('programme:2:Programme 2')),
      );
      final alpha = tester.getTopLeft(
        find.byKey(const ValueKey('programme:1:Programme 1')),
      );
      expect(beta.dy, lessThan(alpha.dy));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '90-minute programme renders at three times a 30-minute programme width',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TvGuideScreen(provider: DurationProvider()),
        ),
      );
      await tester.pumpAndSettle();
      final short = tester
          .getSize(find.byKey(const ValueKey('programme:1:Short')))
          .width;
      final long = tester
          .getSize(find.byKey(const ValueKey('programme:1:Long')))
          .width;
      expect(long, closeTo(short * 3, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('programme width is proportional to duration at the same scale', () {
    expect(
      guideDurationWidth(const Duration(minutes: 90)),
      3 * guideDurationWidth(const Duration(minutes: 30)),
    );
  });

  testWidgets(
    'guide shows schedules for multiple channels and programme details',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: TvGuideScreen(provider: GuideProvider()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Channel Alpha'), findsOneWidget);
      expect(find.text('Channel Beta'), findsOneWidget);
      expect(find.text('Programme 1'), findsNWidgets(2));
      expect(find.text('Programme 2'), findsOneWidget);
      final bars = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bars, hasLength(3));
      for (final bar in bars) {
        expect(bar.value, closeTo(1 / 3, .02));
      }
      await tester.tap(find.text('Programme 2'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Programme description'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
