import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'profiles_locks_test.dart' show config, registry;

void main() {
  testWidgets(
    'all eight supplied portraits are bundled and displayed at matching sizes',
    (tester) async {
      expect(ProfileAvatar.names.length, profileAvatarCount);
      for (var index = 0; index < profileAvatarCount; index++) {
        final name =
            'assets/avatars/photos/portrait_${(index + 1).toString().padLeft(2, '0')}.jpeg';
        final bytes = await rootBundle.load(name);
        expect(bytes.lengthInBytes, greaterThan(0));
        await tester.pumpWidget(
          MaterialApp(home: Center(child: ProfileAvatar(index, size: 96))),
        );
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(ProfileAvatar)), const Size(96, 96));
        expect(
          tester.widget<Image>(find.byType(Image)).image,
          isA<ResizeImage>().having(
            (image) => (image.imageProvider as AssetImage).assetName,
            'bundled photo',
            name,
          ),
        );
        expect(find.byType(ClipOval), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'supplied photo selection survives account storage and reload',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = CredentialStore();
      final session = Session(registry(), store);
      await session.initialize();
      await session.connect(config('photo'), name: 'Photo account', avatar: 7);
      expect(session.activeProfile!.avatar, 7);
      final reloaded = Session(registry(), store);
      await reloaded.initialize();
      expect(reloaded.profiles.single.avatar, 7);
      session.dispose();
      reloaded.dispose();
    },
  );
}
