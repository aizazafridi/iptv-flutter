import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/data/server_http_error.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('403 is logged but replaced with provider-contact guidance for users', () {
    final original = debugPrint;
    final lines = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      final error = serverHttpError(403, service: 'Xtream API');
      expect(
        error.message,
        'The server refused the connection. Please contact your server provider.',
      );
      expect(error.message, isNot(contains('403')));
      expect(lines.single, contains('HTTP 403'));
    } finally {
      debugPrint = original;
    }
  });
  testWidgets(
    'startup edit saves a replacement server without signing in or changing profile identity',
    (tester) async {
      var connections = 0;
      final registry = ProviderRegistry()
        ..register('xtream', 'Xtream Codes', (config) {
          connections++;
          return FakeProvider();
        });
      final appearance = AppAppearance();
      const store = CredentialStore();
      final session = Session(registry, store, appearance: appearance);
      await session.initialize();
      await session.connect(
        const ProviderConfig(
          providerId: 'xtream',
          server: 'https://old.example.com',
          username: 'viewer',
          password: 'secret',
        ),
        name: 'Alex',
      );
      final id = session.activeProfile!.id;
      await session.signOut();
      final before = connections;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage Profiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      fields[1].controller!.text = 'https://new.example.com';
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Manage profiles'), findsOneWidget);
      expect(session.account, isNull);
      expect(connections, before);
      expect(session.profiles.single.id, id);
      expect(session.profiles.single.config.server, 'https://new.example.com');
      expect(
        (await store.loadProfiles())!.single.config.server,
        'https://new.example.com',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
