import '../domain/iptv_provider.dart';
import 'watch_history.dart';
import 'category_locks.dart';
import '../data/locked_provider.dart';
import '../domain/models.dart';
import '../data/xtream/configured_xtream_provider.dart';

typedef ProviderBuilder = IptvProvider Function(ProviderConfig config);

class ProviderRegistry {
  final Map<String, WatchHistory> _histories = {};
  final Map<String, ProviderBuilder> _builders = {
    'starshare': (config) =>
        ConfiguredXtreamProvider(config, name: 'Starshare'),
    'xtream': ConfiguredXtreamProvider.new,
  };
  final Map<String, String> _labels = {
    'starshare': 'Starshare',
    'xtream': 'Xtream Codes',
  };
  Map<String, String> get options => Map.unmodifiable(_labels);
  void register(String id, String label, ProviderBuilder builder) {
    _builders[id] = builder;
    _labels[id] = label;
  }

  IptvProvider create(ProviderConfig config) {
    final builder = _builders[config.providerId];
    if (builder == null) {
      throw const ProviderException('This provider is not installed.');
    }
    final provider = builder(config);
    final scope = WatchHistory.scopeFor(config);
    final history = _histories.putIfAbsent(scope, () => WatchHistory(scope));
    WatchHistory.attach(provider, config, history: history);
    final locks = CategoryLocks(WatchHistory.scopeFor(config));
    final guarded = LockedProvider(provider, locks);
    WatchHistory.attach(guarded, config, history: history);
    CategoryLocks.attach(guarded, locks);
    return guarded;
  }
}
