import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'profiles_locks_test.dart' show config, registry;

void main() {
  testWidgets(
    'switch account returns to chooser and removal is settings only',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final appearance = AppAppearance();
      const store = CredentialStore();
      final session = Session(registry(), store, appearance: appearance);
      await session.initialize();
      await session.connect(config('one'), name: 'Alex');
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Switch account'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch account'));
      await tester.pumpAndSettle();
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byIcon(Icons.person_remove_outlined), findsNothing);
      expect(find.text('Add account'), findsNothing);
      expect((await store.loadProfiles())!.length, 1);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.profiles.length, 1);
      await tester.tap(find.byTooltip('Remove Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(session.profiles, isEmpty);
      expect(await store.loadProfiles(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
