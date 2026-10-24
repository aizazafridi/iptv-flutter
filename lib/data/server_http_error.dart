import 'package:flutter/foundation.dart';
import '../domain/models.dart';

/// Diagnostics intentionally omit URLs, credentials and server response bodies.
ProviderException serverHttpError(int status, {required String service}) {
  debugPrint('[Streamora][$service] Server request failed: HTTP $status.');
  if (status == 403) {
    return const ProviderException(
      'The server refused the connection. Please contact your server provider.',
    );
  }
  return ProviderException('Server returned HTTP $status.');
}
