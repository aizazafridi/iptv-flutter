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
import 'package:iptv_flutter/presentation/profile_loading.dart';
import 'widget_test.dart' show FakeProvider;

class LoadingProvider extends FakeProvider {
  final movies = Completer<List<ContentItem>>(),
      series = Completer<List<ContentItem>>();
  @override
  Future<List<ContentItem>> getAllItems(ContentType type) =>
      type == ContentType.movies ? movies.future : series.future;
}

void main() {
  testWidgets('profile loading checks follow startup completion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FlutterSecureStorage.setMockInitialValues({});
    final provider = LoadingProvider();
    final registry = ProviderRegistry()
      ..register('fixture', 'Fixture', (_) => provider);
    final session = Session(registry, const CredentialStore())..loading = false;
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Alex'), findsNothing);
    expect(find.text('Getting your experience ready...'), findsOneWidget);
    expect(find.text('Loading profile'), findsOneWidget);
    expect(find.text('Syncing watch history'), findsOneWidget);
    expect(find.text('Preparing content'), findsOneWidget);
    var loading = tester.widget<ProfileLoading>(find.byType(ProfileLoading));
    expect(loading.profileLoaded, isTrue);
    expect(loading.historyLoaded, isTrue);
    expect(loading.contentPrepared, isFalse);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    provider.movies.complete([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    loading = tester.widget<ProfileLoading>(find.byType(ProfileLoading));
    expect(loading.contentPrepared, isFalse);
    provider.series.complete([]);
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ProfileLoading), findsNothing);
    expect(session.activeProfile!.name, 'Sam');
    await tester.pumpWidget(const SizedBox());
    session.dispose();
    appearance.dispose();
  });
}
