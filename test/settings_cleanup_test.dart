import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/watch_history.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/settings_screen.dart';
import 'profiles_locks_test.dart' show registry, config;

void main() {
  testWidgets(
    'settings simplify appearance and require confirmation before clearing history',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final session = Session(registry(), const CredentialStore());
      await session.connect(config('settings-cleanup'));
      final history = WatchHistory.forProvider(session.provider!);
      await history.save(
        WatchEntry(
          const ContentItem(
            id: 'movie',
            name: 'Movie',
            type: ContentType.movies,
          ),
          null,
          const Duration(minutes: 1),
          const Duration(hours: 1),
          DateTime.now(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            session: session,
            appearance: AppAppearance(),
            switchUser: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Player settings'), findsNothing);
      await tester.tap(find.text('Appearance and browsing'));
      await tester.pumpAndSettle();
      expect(find.text('Color'), findsOneWidget);
      for (final label in ['Live TV cards', 'Movies cards', 'Series cards']) {
        expect(find.text(label), findsNothing);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Storage and history'));
      await tester.tap(find.text('Storage and history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear watch history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies only'));
      await tester.pumpAndSettle();
      expect(find.text('Clear watch history?'), findsOneWidget);
      expect(await history.entries(), hasLength(1));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await history.entries(), hasLength(1));
      await tester.tap(find.text('Clear watch history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movies only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear history'));
      await tester.pumpAndSettle();
      expect(await history.entries(), isEmpty);
      await tester.tap(find.text('Delete all recordings'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all recordings?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all recordings?'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
}
