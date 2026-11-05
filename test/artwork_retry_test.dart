import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/artwork_retry.dart';

void main() {
  testWidgets('missing metadata recovers while page remains open', (
    tester,
  ) async {
    final scope = ArtworkRetryScope();
    var calls = 0;
    final future = retryArtwork<String?>(
      scope: scope,
      load: () async => ++calls < 3 ? null : 'artwork',
      usable: (value) => value != null,
      active: () => true,
    );
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 6));
    expect(await future, 'artwork');
    expect(calls, 3);
    scope.dispose();
  });
  testWidgets('retries are bounded and closing the page cancels waiting', (
    tester,
  ) async {
    final scope = ArtworkRetryScope();
    var calls = 0;
    final future = retryArtwork<String?>(
      scope: scope,
      load: () async {
        calls++;
        throw Exception('temporary');
      },
      usable: (value) => value != null,
      active: () => true,
    );
    await tester.pump();
    for (final seconds in [2, 6, 15]) {
      await tester.pump(Duration(seconds: seconds));
    }
    expect(await future, isNull);
    expect(calls, 4);
    scope.dispose();
    final cancelled = ArtworkRetryScope();
    final pending = retryArtwork<String?>(
      scope: cancelled,
      load: () async {
        calls++;
        return null;
      },
      usable: (value) => value != null,
      active: () => true,
    );
    await tester.pump();
    cancelled.dispose();
    await tester.pump(const Duration(seconds: 30));
    expect(await pending, isNull);
    expect(calls, 5);
  });
}
