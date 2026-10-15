import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'profiles_locks_test.dart' show config, registry;

void main() {
  test('legacy supplied photos migrate and new selections round trip', () {
    for (var old = 0; old < 38; old++) {
      final json = AccountProfile(
        id: 'saved',
        name: 'Saved',
        avatar: old,
        config: config('user'),
      ).toJson()..remove('avatarSet');
      final profile = AccountProfile.fromJson(json);
      expect(profile.avatar, old >= 30 ? old - 30 : 0);
      expect(AccountProfile.fromJson(profile.toJson()).avatar, profile.avatar);
      expect(profile.id, 'saved');
    }
    expect(ProfileAvatar.names.length, 8);
  });

  testWidgets(
    'header portrait opens account name, expiry and edit with clean dashboard',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final appearance = AppAppearance();
      final session = Session(
        registry(),
        const CredentialStore(),
        appearance: appearance,
      );
      await session.initialize();
      await session.connect(config('viewer'), name: 'My profile', avatar: 7);
      session.account = Account('viewer', 'Active', DateTime.utc(2030, 5, 6));
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What are we watching?'), findsOneWidget);
      expect(find.text('My profile'), findsNothing);
      expect(find.textContaining('Expires'), findsNothing);
      expect(tester.widget<ProfileAvatar>(find.byType(ProfileAvatar)).index, 7);
      expect(
        (tester.getCenter(find.byTooltip('Current account')).dx -
                tester.getCenter(find.byTooltip('Settings')).dx)
            .abs(),
        lessThan(65),
      );
      await tester.tap(find.byTooltip('Current account'));
      await tester.pumpAndSettle();
      expect(find.text('My profile'), findsOneWidget);
      expect(find.textContaining('2030'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit account'), findsOneWidget);
      expect(find.byType(ProfileAvatar), findsNWidgets(8));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'My profile',
      );
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
