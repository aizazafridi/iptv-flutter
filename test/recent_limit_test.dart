import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/recent_items.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  test('recent movies and series contain only the 50 newest titles', () {
    for (final type in [ContentType.movies, ContentType.series]) {
      final rows = recentlyAdded(
        List.generate(
          80,
          (i) => ContentItem(
            id: '$i',
            name: 'Title $i',
            type: type,
            addedAt: DateTime.utc(2026).add(Duration(days: i)),
          ),
        ),
      );
      expect(rows.length, 50);
      expect(rows.first.id, '79');
      expect(rows.last.id, '30');
    }
  });
}
