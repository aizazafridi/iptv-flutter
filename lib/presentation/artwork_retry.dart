import 'dart:async';
import '../application/browsing_mode.dart';

class ArtworkRetryScope {
  bool disposed = false;
  final pending = <Timer, Completer<void>>{};
  Future<void> wait(Duration duration) {
    final completion = Completer<void>();
    late Timer timer;
    timer = Timer(duration, () {
      pending.remove(timer);
      completion.complete();
    });
    pending[timer] = completion;
    return completion.future;
  }

  void dispose() {
    disposed = true;
    for (final entry in pending.entries) {
      entry.key.cancel();
      entry.value.complete();
    }
    pending.clear();
  }
}

/// A few sequential retries; never issue work after the page leaves or in Lite.
Future<T?> retryArtwork<T>({
  required ArtworkRetryScope scope,
  required Future<T> Function() load,
  required bool Function(T) usable,
  required bool Function() active,
  List<Duration> delays = const [
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 15),
  ],
}) async {
  for (var attempt = 0; attempt <= delays.length; attempt++) {
    if (scope.disposed || !active() || BrowsingModeSettings.instance.lite) {
      return null;
    }
    if (attempt > 0) await scope.wait(delays[attempt - 1]);
    if (scope.disposed || !active() || BrowsingModeSettings.instance.lite) {
      return null;
    }
    try {
      final value = await load();
      if (usable(value)) return value;
    } catch (_) {
      // A transient lookup failure must not leave the open page stuck forever.
    }
  }
  return null;
}
