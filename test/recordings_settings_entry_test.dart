import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/category_lock_settings_screen.dart';
import 'profiles_locks_test.dart' show CatalogFixture;

void main() {
  testWidgets(
    'recordings have dedicated shared controls and are absent from media category settings',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = CatalogFixture();
      final locks = CategoryLocks('recordings-settings-entry');
      CategoryLocks.attach(provider, locks);
      await locks.setPassword('123456');
      for (final type in ContentType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: CategoryLockSettingsScreen(
              key: ValueKey(type),
              provider: provider,
              type: type,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Recordings'), findsNothing);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: CategoryLockSettingsScreen(
            provider: provider,
            recordingsOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recordings'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      for (final type in ContentType.values) {
        final category = CategoryLocks.recordingsCategory(type);
        expect(locks.hidden(category), isTrue);
        expect(locks.configured(category), isTrue);
      }
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
