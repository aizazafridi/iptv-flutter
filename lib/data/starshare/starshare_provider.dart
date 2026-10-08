import '../../domain/models.dart';
import '../xtream/xtream_client.dart';
import '../xtream/xtream_provider.dart';

/// Starshare currently uses Xtream. Service-specific changes belong here.
class StarshareProvider extends XtreamProvider {
  StarshareProvider(ProviderConfig config)
    : super(XtreamClient(config), displayName: 'Starshare');
}
