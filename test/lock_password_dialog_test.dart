import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/presentation/lock_password_dialog.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final size in [const Size(960, 540), const Size(1920, 1080)]) {
    testWidgets(
      'compact PIN dialog shows all six glyphs and unlocks at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final locks = CategoryLocks('pin-size');
        await locks.setPassword('012345');
        String? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => LockPasswordDialog(locks: locks),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: find.byType(AlertDialog),
                      matching: find.byWidgetPredicate(
                        (widget) =>
                            widget is Material &&
                            widget.type == MaterialType.card,
                      ),
                    )
                    .first,
              )
              .width,
          lessThanOrEqualTo(340),
        );
        final field = find.byKey(const ValueKey('parental-pin'));
        await tester.enterText(field, '012345');
        await tester.pump(const Duration(seconds: 2));
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        expect(editable.widget.controller.text, '012345');
        expect(editable.widget.obscureText, isTrue);
        final last = editable.renderEditable.getBoxesForSelection(
          const TextSelection(baseOffset: 5, extentOffset: 6),
        );
        expect(last, isNotEmpty);
        expect(
          last.last.right,
          lessThanOrEqualTo(editable.renderEditable.size.width),
        );
        expect(last.last.left, greaterThanOrEqualTo(0));
        await tester.tap(find.byTooltip('Show PIN'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).obscureText, isFalse);
        expect(tester.widget<TextField>(field).controller!.text, '012345');
        await tester.tap(find.text('Unlock'));
        await tester.pumpAndSettle();
        expect(result, '012345');
        expect(find.byType(LockPasswordDialog), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        locks.dispose();
      },
    );
  }
  testWidgets(
    'changing PIN fits with keyboard and preserves current/new six-digit codes',
    (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final locks = CategoryLocks('pin-change');
      await locks.setPassword('654321');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) =>
                      LockPasswordDialog(locks: locks, setting: true),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('current-parental-pin')),
        '654321',
      );
      await tester.enterText(
        find.byKey(const ValueKey('parental-pin')),
        '123456',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(locks.check('123456'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      locks.dispose();
    },
  );
}
