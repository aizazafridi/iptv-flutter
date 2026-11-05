import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/history_removal.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/presentation/profile_selection_screen.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'profile_selection_redesign_test.dart' show profiles;
import 'widget_test.dart' show FakeProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'removing series removes every unfinished episode, preserves other titles and profiles',
    () async {
      final history = WatchHistory('a');
      const series = ContentItem(
        id: '1',
        name: 'Series',
        type: ContentType.series,
      );
      const movie = ContentItem(
        id: '1',
        name: 'Movie',
        type: ContentType.movies,
      );
      for (final episode in [1, 2]) {
        await history.save(
          WatchEntry(
            series,
            Episode(
              id: '$episode',
              title: 'Episode',
              season: 1,
              number: episode,
              extension: 'mp4',
            ),
            const Duration(minutes: 2),
            const Duration(minutes: 20),
            DateTime.now(),
          ),
        );
      }
      await history.save(
        WatchEntry(
          movie,
          null,
          const Duration(minutes: 2),
          const Duration(minutes: 20),
          DateTime.now(),
        ),
      );
      await WatchHistory('b').save(
        WatchEntry(
          series,
          null,
          const Duration(minutes: 2),
          const Duration(minutes: 20),
          DateTime.now(),
        ),
      );
      await history.removeTitle(series);
      expect(
        (await WatchHistory('a').entries()).single.item.type,
        ContentType.movies,
      );
      expect(await WatchHistory('b').entries(), hasLength(1));
    },
  );
  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.select]) {
    testWidgets('remote short OK opens, long OK confirms removal with $key', (
      tester,
    ) async {
      const item = ContentItem(
        id: '1',
        name: 'Movie',
        type: ContentType.movies,
      );
      final history = WatchHistory('remote');
      await history.save(
        WatchEntry(
          item,
          null,
          const Duration(minutes: 2),
          const Duration(minutes: 20),
          DateTime.now(),
        ),
      );
      final node = FocusNode();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                width: 200,
                height: 320,
                child: SeriesPosterCard(
                  item: item,
                  provider: FakeProvider(),
                  focusNode: node,
                  onOpen: () => opened++,
                  onRemove: () => confirmHistoryRemoval(context, history, item),
                ),
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(opened, 1);
      await tester.sendKeyDownEvent(key);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
      expect(find.text('Remove from watch history?'), findsOneWidget);
      expect(opened, 1);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(await history.entries(), hasLength(1));
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(key);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(await history.entries(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      node.dispose();
    });
  }
  testWidgets(
    'profile focus outlines avatar and name together and compact sizes',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileSelectionScreen(
              profiles: profiles(5),
              onSelect: (_) async {},
              onManage: (_) async {},
              onAdd: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('profile-card-profile-0'));
      expect(
        find.descendant(of: card, matching: find.text('Viewer 0')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(ProfileAvatar)),
        findsOneWidget,
      );
      expect(
        (tester.widget<AnimatedContainer>(card).decoration as BoxDecoration)
            .border!
            .top
            .color,
        const Color(0xff64b5f6),
      );
      expect(
        tester.widget<Text>(find.text('Choose your profile')).style!.fontSize,
        30,
      );
      expect(
        tester.widget<ProfileAvatar>(find.byType(ProfileAvatar).first).size,
        lessThanOrEqualTo(112),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final next = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('profile-card-profile-1')),
      );
      expect(
        (next.decoration as BoxDecoration).border!.top.color,
        const Color(0xff64b5f6),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
