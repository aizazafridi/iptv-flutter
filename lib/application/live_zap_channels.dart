import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../data/locked_provider.dart';
import 'category_locks.dart';
import 'my_list.dart';
import 'live_favourite_groups.dart';

Future<List<ContentItem>> liveZapChannels({
  required IptvProvider? provider,
  required Future<List<ContentItem>> Function() load,
  String? categoryId,
  String? groupId,
}) async {
  List<ContentItem> rows;
  if (provider != null && categoryId == 'favorites') {
    final groups = LiveFavouriteGroups.forProvider(provider);
    await groups.load();
    rows = groups.channels(
      groupId ?? groups.selectedGroup,
      await MyList.forProvider(provider).items(ContentType.live),
    );
  } else if (provider != null && categoryId != null && categoryId != 'all') {
    rows = await provider.getItems(Category(categoryId, '', ContentType.live));
  } else {
    rows = await load();
  }
  if (provider is LockedProvider) {
    return provider.visibleSavedItems(rows, excludeConfiguredLocks: true);
  }
  if (provider != null) {
    return CategoryLocks.forProvider(
      provider,
    ).visibleItems(rows, excludeConfiguredLocks: true);
  }
  return rows;
}
