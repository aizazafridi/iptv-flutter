import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/phone_companion_server.dart';
import 'package:iptv_flutter/presentation/phone_companion_panel.dart';

void main() {
  testWidgets('TV pairing panel fits 960x540 and keeps enable opt-in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = PhoneCompanionServer(
      page: '',
      isCurrentProfile: () => true,
      dispatch: (_, _) async => {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PhoneCompanionPanel(server: server),
              ),
              child: const Text('Phone'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Phone'));
    await tester.pumpAndSettle();
    expect(server.running, false);
    expect(find.text('Enable phone access'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PhoneCompanionPanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('enabled TV panel shows QR, address and code without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = PhoneCompanionServer(
      page: '',
      isCurrentProfile: () => true,
      dispatch: (_, _) async => {},
    );
    await tester.runAsync(
      () => server.start(address: InternetAddress.loopbackIPv4),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PhoneCompanionPanel(server: server),
              ),
              child: const Text('Phone'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Phone'));
    await tester.pumpAndSettle();
    expect(find.text(server.code), findsOneWidget);
    expect(find.text(server.urls.single), findsOneWidget);
    expect(find.text('Disconnect all phones'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(server.stop);
  });
}
