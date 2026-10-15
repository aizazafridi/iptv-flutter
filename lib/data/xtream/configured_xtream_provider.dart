import '../../domain/models.dart';
import 'xtream_client.dart';
import 'xtream_provider.dart';

/// Creates the shared Xtream adapter from account configuration.
class ConfiguredXtreamProvider extends XtreamProvider {
  ConfiguredXtreamProvider(
    ProviderConfig config, {
    String name = 'Xtream Codes',
  }) : super(XtreamClient(config), displayName: name);
}
