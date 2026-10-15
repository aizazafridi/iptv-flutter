import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'profiles_locks_test.dart' show config, registry;
import 'widget_test.dart' show FakeProvider;

class RejectingProvider extends FakeProvider {
  @override
  Future<Account> connect() async =>
      throw const ProviderException('Login rejected');
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'editing at the five-account limit preserves ID, settings and profile count',
    () async {
      const store = CredentialStore();
      final appearance = AppAppearance();
      final session = Session(registry(), store, appearance: appearance);
      await session.initialize();
      for (var i = 0; i < 5; i++) {
        await session.connect(config('user$i'), name: 'Viewer $i');
      }
      final original = session.activeProfile!;
      final connection = session.provider;
      await appearance.choose('Navy');
      expect(
        await session.updateCurrentProfile(
          original.config,
          name: 'Updated',
          avatar: 7,
        ),
        isTrue,
      );
      expect(session.provider, same(connection));
      expect(session.activeProfile!.id, original.id);
      expect(session.activeProfile!.avatar, 7);
      expect(session.profiles.length, 5);
      expect(appearance.selected, 'Navy');
      expect(
        await session.updateCurrentProfile(
          config('new-login'),
          name: 'New login',
          avatar: 2,
        ),
        isTrue,
      );
      expect(session.activeProfile!.id, original.id);
      expect(session.activeProfile!.config.profileId, original.id);
      expect(session.provider, isNot(same(connection)));
      expect((await store.loadProfiles())!.last.config.username, 'new-login');
      expect(appearance.selected, 'Navy');
      session.dispose();
      appearance.dispose();
    },
  );

  test(
    'failed credential edits keep the working account and saved credentials',
    () async {
      const store = CredentialStore();
      final session = Session(registry(), store);
      await session.initialize();
      await session.connect(config('working'), name: 'Working');
      final original = session.activeProfile;
      final connection = session.provider;
      session.registry.register('reject', 'Reject', (_) => RejectingProvider());
      expect(
        await session.updateCurrentProfile(
          const ProviderConfig(
            providerId: 'reject',
            server: 'https://example.com',
            username: 'bad',
            password: 'bad',
          ),
          name: 'Changed',
          avatar: 7,
        ),
        isFalse,
      );
      expect(session.provider, same(connection));
      expect(session.activeProfile, same(original));
      expect(session.error, 'Login rejected');
      expect((await store.loadProfiles())!.single.name, 'Working');
      expect(session.loading, isFalse);
      session.dispose();
    },
  );

  testWidgets(
    'settings edits the current account and Cancel discards changes',
    (tester) async {
      final appearance = AppAppearance();
      final session = Session(
        registry(),
        const CredentialStore(),
        appearance: appearance,
      );
      await session.initialize();
      await session.connect(config('viewer'), name: 'Original', avatar: 1);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit current account'));
      await tester.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'Original',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller!.text,
        'viewer',
      );
      await tester.enterText(fields.first, 'Edited');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(session.activeProfile!.name, 'Edited');
      expect(session.activeProfile!.avatar, 1);
      expect(session.profiles.length, 1);
      await tester.tap(find.text('Edit current account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Discard');
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.activeProfile!.name, 'Edited');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
