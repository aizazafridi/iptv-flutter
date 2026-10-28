import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/player_drawer.dart';

void main() {
  test(
    'track labels remove redundant known codes and retain qualifiers and IDs',
    () {
      final options = playerTrackOptions([
        (id: '1', label: 'English \u00b7 eng'),
        (id: '2', label: 'English \u00b7 eng \u00b7 Forced'),
        (id: '3', label: 'English \u00b7 SDH'),
        (id: '4', label: 'Chinese (Simplified) \u00b7 zho'),
        (id: '5', label: 'ara'),
        (id: '6', label: 'Unusual language qaa'),
      ]);
      expect(options.map((o) => o.label), [
        'English',
        'English \u00b7 Forced',
        'English \u00b7 SDH',
        'Chinese (Simplified)',
        'Arabic',
        'Unusual language qaa',
      ]);
      expect(options.map((o) => o.id), ['1', '2', '3', '4', '5', '6']);
      expect(
        playerTrackOptions([
          (id: 'a', label: 'English'),
          (id: 'b', label: 'eng'),
        ]).map((o) => o.label),
        ['English \u00b7 Track 1', 'English \u00b7 Track 2'],
      );
    },
  );
  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets(
      'compact full-height drawer separates selection and focus at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? chosen;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Open'),
                  onPressed: () async {
                    chosen = await showPlayerOptions(
                      context,
                      title: 'Subtitles',
                      selected: 'no',
                      options: const [
                        PlayerOption('no', 'Off'),
                        PlayerOption('auto', 'Automatic'),
                        PlayerOption('en', 'English'),
                        PlayerOption(
                          'url',
                          'Add subtitle URL',
                          section: 'External Subtitles',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const ValueKey('player-drawer')),
        );
        expect(rect.width, closeTo(size.width * .3, .1));
        expect(rect.height, size.height);
        final off = find.byKey(const ValueKey('player-option-no'));
        final automatic = find.byKey(const ValueKey('player-option-auto'));
        expect(tester.getSize(off).height, 46);
        expect(find.byIcon(Icons.check), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(chosen, isNull);
        final selected = tester.widget<TextButton>(off);
        final focused = tester.widget<TextButton>(automatic);
        expect(
          selected.style!.backgroundColor!.resolve({}),
          isNot(focused.style!.backgroundColor!.resolve({WidgetState.focused})),
        );
        expect(
          focused.style!.side!.resolve({WidgetState.focused})!.color,
          const Color(0xff64b5f6),
        );
        expect(selected.style!.side!.resolve({})!.color, Colors.transparent);
        expect(find.text('External Subtitles'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('External Subtitles')).dy,
          greaterThan(tester.getBottomLeft(find.text('English')).dy),
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(chosen, isNull);
        expect(find.byKey(const ValueKey('player-drawer')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'selected track outside initial viewport receives focus without selecting it',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  chosen = await showPlayerOptions(
                    context,
                    title: 'Audio',
                    selected: '27',
                    options: List.generate(
                      30,
                      (i) => PlayerOption('$i', 'Track $i'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Track 27'), findsOneWidget);
      expect(chosen, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, '27');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
