import 'package:flutter/material.dart';
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
