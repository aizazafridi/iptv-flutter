import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'widget_test.dart' show FakeProvider;

void main() {
  for (final type in [ContentType.movies, ContentType.series]) {
    testWidgets('$type expands width while preserving height on focus', (
      tester,
    ) async {
      final node = FocusNode();
      final other = FocusNode();
      final provider = FakeProvider();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TextButton(
                  focusNode: other,
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('Other'),
                ),
                SizedBox(
                  width: 220,
                  height: 380,
                  child: SeriesPosterCard(
                    item: ContentItem(
                      id: '1',
                      name: 'Title',
                      type: type,
                      releaseYear: 2026,
                      rating: 8.1,
                    ),
                    provider: provider,
                    focusNode: node,
                    onOpen: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final body = find
          .descendant(
            of: find.byType(SeriesPosterCard),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      final initial = tester.getSize(body);
      if (type == ContentType.movies) {
        expect(find.textContaining('8.1/10'), findsNothing);
      }
      node.requestFocus();
      await tester.pumpAndSettle();
      final focused = tester.getSize(body);
      if (type == ContentType.movies) {
        expect(find.textContaining('8.1/10'), findsOneWidget);
      }
      expect(
        focused.width,
        closeTo(initial.width * (type == ContentType.movies ? 1.28 : 1.22), .1),
      );
      expect(focused.height, initial.height);
      expect(focused.width, lessThanOrEqualTo(220.01));
      other.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.getSize(body), initial);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      node.dispose();
      other.dispose();
      provider.dispose();
    });
  }
}
