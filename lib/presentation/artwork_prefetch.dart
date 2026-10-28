import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Small shared queue: never lets artwork warming compete with playback en masse.
class ArtworkPrefetch {
  static final _queue = Queue<Future<void> Function()>();
  static final _seen = <String>{};
  static int _active = 0;
  static void images(
    BuildContext context,
    Iterable<Uri?> images, {
    int width = 342,
    int limit = 4,
  }) {
    for (final uri in images.whereType<Uri>().take(limit)) {
      if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) continue;
      final key = '$width:$uri';
      if (_seen.contains(key) || _queue.length >= 12) continue;
      if (_seen.length >= 200) _seen.remove(_seen.first);
      _seen.add(key);
      _queue.add(() async {
        if (!context.mounted) {
          _seen.remove(key);
          return;
        }
        var failed = false;
        try {
          await precacheImage(
            ResizeImage.resizeIfNeeded(
              width,
              null,
              CachedNetworkImageProvider(uri.toString(), maxWidth: width),
            ),
            context,
            onError: (_, _) {
              failed = true;
            },
          );
        } catch (_) {
          failed = true;
        }
        if (failed) _seen.remove(key);
      });
    }
    _drain();
  }

  static void _drain() {
    while (_active < 2 && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active++;
      unawaited(
        job().whenComplete(() {
          _active--;
          _drain();
        }),
      );
    }
  }
}
