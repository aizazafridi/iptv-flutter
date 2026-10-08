import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../data/starshare/starshare_provider.dart';
import '../data/xtream/xtream_client.dart';
import '../data/xtream/xtream_provider.dart';

typedef ProviderBuilder = IptvProvider Function(ProviderConfig config);

class ProviderRegistry {
  final Map<String, ProviderBuilder> _builders = {
    'starshare': StarshareProvider.new,
    'xtream': (config) => XtreamProvider(XtreamClient(config)),
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
    return builder(config);
  }
}
