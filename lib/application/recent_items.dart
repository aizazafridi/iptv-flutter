import '../domain/models.dart';

/// Recently added spans all categories. Unknown dates cannot establish recency.
List<ContentItem> recentlyAdded(List<ContentItem> catalog) {
  final seen = <String>{};
  final items = catalog
      .where((item) => item.addedAt != null && seen.add(item.id))
      .toList();
  items.sort((a, b) {
    final date = b.addedAt!.compareTo(a.addedAt!);
    return date == 0 ? a.id.compareTo(b.id) : date;
  });
  return items;
}
