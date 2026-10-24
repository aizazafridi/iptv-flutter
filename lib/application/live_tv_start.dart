import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../data/last_live_channel.dart';
import 'my_list.dart';
import 'category_locks.dart';

class LiveTvStart {
  final ContentItem channel;
  final PlaybackSource source;
  final bool firstUse;
  const LiveTvStart(this.channel, this.source, this.firstUse);
}

Future<LiveTvStart> prepareLiveTv(IptvProvider provider) async {
  final locks = CategoryLocks.forProvider(provider);
  await locks.load();
  final last = await LastLiveChannel.forProvider(provider).load();
  final seen = <String>{};
  Future<LiveTvStart?> attempt(List<ContentItem> rows) async {
    for (final item in rows) {
      if (!seen.add(item.id) ||
          locks.titleHidden(item) ||
          locks.titleLocked(item)) {
        continue;
      }
      if (item.categoryId != null) {
        final category = Category(item.categoryId!, '', ContentType.live);
        if (locks.hidden(category) || locks.isLocked(category)) continue;
      }
      try {
        return LiveTvStart(
          item,
          await provider.resolvePlayback(item),
          last == null,
        );
      } on ProviderException {
        /* Try another available, accessible channel. */
      }
    }
    return null;
  }

  if (last != null) {
    final result = await attempt([last]);
    if (result != null) return result;
  }
  final favourite = await attempt(
    await MyList.forProvider(provider).items(ContentType.live),
  );
  if (favourite != null) return favourite;
  final fallback = await attempt(await provider.getAllItems(ContentType.live));
  if (fallback != null) return fallback;
  throw const ProviderException(
    'No accessible Live TV channels are available.',
  );
}
