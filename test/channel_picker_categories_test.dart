import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/presentation/channel_picker.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  testWidgets(
    'split-screen picker shows categories before channels and returns to categories',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      var fallbackCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelPicker(
            title: 'Choose channel - Screen 2',
            categoriesFirst: true,
            provider: FakeProvider(),
            load: () async {
              fallbackCalls++;
              return [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('English (4K)'), findsOneWidget);
      expect(find.text('Example title'), findsNothing);
      expect(fallbackCalls, 0);
      await tester.tap(find.text('English (4K)'));
      await tester.pumpAndSettle();
      expect(find.text('Example title'), findsOneWidget);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(find.text('English (4K)'), findsOneWidget);
      expect(find.text('Example title'), findsNothing);
    },
  );
}
