import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'widget_test.dart' show FakeProvider;

class PlaylistFixture extends FakeProvider {
  @override
  Set<ContentType> get supportedTypes => {ContentType.live};
}

void main() {
  testWidgets(
    'startup Add profile opens connection choices and Cancel returns to chooser',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final appearance = AppAppearance();
      final session = Session(
        ProviderRegistry(),
        const CredentialStore(),
        appearance: appearance,
      );
      await session.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add profile'));
      await tester.pumpAndSettle();
      expect(find.text('Connection type'), findsOneWidget);
      await tester.tap(find.text('Xtream Codes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3U Playlist').last);
      await tester.pumpAndSettle();
      expect(find.text('M3U playlist URL'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text("Who's watching?"), findsOneWidget);
      expect(find.text('Add profile'), findsOneWidget);
      expect(session.profiles, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );

  testWidgets(
    'M3U account asks for playlist URL without Xtream credentials and saves its type',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final registry = ProviderRegistry();
      ProviderConfig? captured;
      registry.register('m3u', 'M3U Playlist', (config) {
        captured = config;
        return PlaylistFixture();
      });
      const store = CredentialStore();
      final appearance = AppAppearance();
      final session = Session(registry, store, appearance: appearance);
      await session.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HomeScreen(
                      session: session,
                      appearance: appearance,
                      addAccountOnly: true,
                    ),
                  ),
                ),
                child: const Text('Add'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xtream Codes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('M3U Playlist').last);
      await tester.pumpAndSettle();
      expect(find.text('M3U playlist URL'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
      expect(find.text('Password'), findsNothing);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields, hasLength(2));
      fields[0].controller!.text = 'Playlist account';
      fields[1].controller!.text =
          'https://example.com/playlist.m3u?token=secret';
      await tester.ensureVisible(find.text('Connect'));
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(captured?.providerId, 'm3u');
      expect(captured?.username, isEmpty);
      expect(captured?.password, isEmpty);
      final profiles = await store.loadProfiles();
      expect(profiles!.single.config.providerId, 'm3u');
      expect(profiles.single.name, 'Playlist account');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
