import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/session.dart';
import 'package:iptv_flutter/application/provider_registry.dart';
import 'package:iptv_flutter/data/credential_store.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/home_screen.dart';
import 'package:iptv_flutter/presentation/profile_avatar.dart';
import 'widget_test.dart' show FakeProvider;

class LoadingProvider extends FakeProvider {
  final movies = Completer<List<ContentItem>>(),
      series = Completer<List<ContentItem>>();
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) =>
      type == ContentType.movies ? movies.future : series.future;
}

void main() {
  testWidgets(
    'selected profile centers alone with smoothly interpolated progress until loading finishes',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      final provider = LoadingProvider();
      final registry = ProviderRegistry()
        ..register('fixture', 'Fixture', (_) => provider);
      final session = Session(registry, const CredentialStore())
        ..loading = false;
      session.profiles = [
        for (final name in ['Alex', 'Sam'])
          AccountProfile(
            id: name,
            name: name,
            avatar: 0,
            config: ProviderConfig(
              providerId: 'fixture',
              profileId: name,
              server: 'https://example.com',
              username: name,
              password: 'test',
            ),
          ),
      ];
      final appearance = AppAppearance();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(session: session, appearance: appearance),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Alex'), findsNothing);
      expect(find.byType(ProfileAvatar), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester.getCenter(find.byType(ProfileAvatar)).dx,
        closeTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
          1,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final before = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      provider.movies.complete([]);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final middle = tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value!;
      expect(middle, greaterThan(before));
      expect(middle, lessThan(0.65));
      provider.series.complete([]);
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(session.activeProfile!.name, 'Sam');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      appearance.dispose();
    },
  );
}
