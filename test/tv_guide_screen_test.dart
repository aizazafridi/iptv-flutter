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

void main() {
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
      expect(find.text('Programme 1'), findsOneWidget);
      expect(find.text('Programme 2'), findsOneWidget);
      final bars = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bars, hasLength(2));
      for (final bar in bars) {
        expect(bar.value, closeTo(1 / 3, .02));
      }
      await tester.tap(find.text('Programme 2'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Programme description'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
