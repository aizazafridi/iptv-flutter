import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/settings_screen.dart';
import 'package:iptv_flutter/presentation/category_lock_settings_screen.dart';
import 'profiles_locks_test.dart' show CatalogFixture, registry, config;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('Settings cards open separate panels and Back returns to cards', (
    tester,
  ) async {
    final session = Session(registry(), const CredentialStore());
    await session.connect(config('settings-cards'));
    final appearance = AppAppearance();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          session: session,
          appearance: appearance,
          switchUser: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Profile settings'), findsOneWidget);
    expect(find.text('Playback defaults'), findsNothing);
    await tester.tap(find.text('Player settings'));
    await tester.pumpAndSettle();
    expect(find.text('Playback defaults'), findsOneWidget);
    expect(find.text('Profile settings'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Profile settings'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    appearance.dispose();
  });
  testWidgets('remote reaches PIN from Hide and retains focus after saving', (
    tester,
  ) async {
    final provider = CatalogFixture();
    final locks = CategoryLocks('pin-focus');
    CategoryLocks.attach(provider, locks);
    await locks.setPassword('123456');
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryLockSettingsScreen(
          provider: provider,
          type: ContentType.movies,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hide = tester.widget<Switch>(find.byType(Switch).at(0));
    hide.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final pin = tester.widget<Switch>(find.byType(Switch).at(1));
    expect(pin.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      locks.configured(const Category('7', '', ContentType.movies)),
      isTrue,
    );
    expect(pin.focusNode!.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(hide.focusNode!.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
