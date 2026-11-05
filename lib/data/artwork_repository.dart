import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../application/browsing_mode.dart';

enum ArtworkPriority { visible, backdrop, nearVisible, cast }

enum ArtworkKind { poster, cast, episode, backdrop, logo }

/// Opt-in, bounded telemetry. Never records URLs, filenames, queries or credentials.
class ArtworkMetrics {
  static bool enabled = const bool.fromEnvironment('ARTWORK_METRICS');
  static final events = <Map<String, Object?>>[];
  static bool _installed = false;
  static int peakImageBytes = 0;
  static final fileReadyUs = <String, int>{};
  static int frames = 0, buildOverBudget = 0, rasterOverBudget = 0;
  static int refreshHz = 60;
  static void exportSnapshot() {
    if (!enabled) return;
    record(
      'snapshot',
      values: {
        'frames': frames,
        'build_over_budget': buildOverBudget,
        'raster_over_budget': rasterOverBudget,
        'refresh_hz': refreshHz,
        'peak_cached_image_bytes': peakImageBytes,
      },
    );
  }

  static String id(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 20);
  static void record(
    String phase, {
    String? url,
    Map<String, Object?> values = const {},
  }) {
    if (!enabled) return;
    final event = <String, Object?>{
      'phase': phase,
      'us': DateTime.now().microsecondsSinceEpoch,
      if (url != null) 'id': id(url),
      ...values,
    };
    if (events.length >= 2000) events.removeAt(0);
    events.add(event);
    developer.Timeline.instantSync('artwork.$phase', arguments: event);
    developer.log(jsonEncode(event), name: 'streamora.artwork');
    if (phase != 'frame' && phase != 'image_cache') {
      debugPrint('ARTWORK_METRIC ${jsonEncode(event)}');
    }
  }

  static void install() {
    if (!enabled || _installed) return;
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback((frames) {
      for (final frame in frames) {
        ArtworkMetrics.frames++;
        final budget = 1000000 / refreshHz;
        if (frame.buildDuration.inMicroseconds > budget) buildOverBudget++;
        if (frame.rasterDuration.inMicroseconds > budget) rasterOverBudget++;
        record(
          'frame',
          values: {
            'build_us': frame.buildDuration.inMicroseconds,
            'raster_us': frame.rasterDuration.inMicroseconds,
          },
        );
      }
      if (ArtworkMetrics.frames % 120 < frames.length) exportSnapshot();
      sampleMemory();
    });
  }

  static void sampleMemory() {
    if (!enabled) return;
    final cache = PaintingBinding.instance.imageCache;
    if (cache.currentSizeBytes > peakImageBytes) {
      peakImageBytes = cache.currentSizeBytes;
    }
    record(
      'image_cache',
      values: {
        'bytes': cache.currentSizeBytes,
        'peak_bytes': peakImageBytes,
        'live': cache.liveImageCount,
        'pending': cache.pendingImageCount,
      },
    );
  }
}

class ArtworkCancelled implements Exception {
  const ArtworkCancelled();
}

class _Job {
  final String key;
  final ArtworkPriority Function() priority;
  final bool Function() wanted;
  final Future<Object?> Function() work;
  final completer = Completer<Object?>();
  _Job(this.key, this.priority, this.wanted, this.work);
}

/// Four visible/backdrop slots and one background slot, held through body download.
class ArtworkQueue {
  final int foregroundLimit, backgroundLimit;
  int foreground = 0, background = 0;
  final _pending = <_Job>[];
  final _jobs = <String, _Job>{};
  ArtworkQueue({this.foregroundLimit = 4, this.backgroundLimit = 1});
  Future<T> run<T>(
    String key,
    Future<T> Function() work, {
    required ArtworkPriority Function() priority,
    bool Function()? wanted,
  }) {
    final existing = _jobs[key];
    if (existing != null) {
      ArtworkMetrics.record('inflight_join', url: key);
      return existing.completer.future.then((v) => v as T);
    }
    final job = _Job(
      key,
      priority,
      wanted ?? () => true,
      () async => await work(),
    );
    _jobs[key] = job;
    _pending.add(job);
    scheduleMicrotask(drain);
    return job.completer.future.then((v) => v as T);
  }

  void drain() {
    _pending.sort((a, b) => a.priority().index.compareTo(b.priority().index));
    for (final job in List<_Job>.from(_pending)) {
      if (!job.wanted()) {
        _pending.remove(job);
        _jobs.remove(job.key);
        job.completer.completeError(const ArtworkCancelled());
        continue;
      }
      final fg = job.priority().index <= ArtworkPriority.backdrop.index;
      if (fg ? foreground >= foregroundLimit : background >= backgroundLimit) {
        continue;
      }
      _pending.remove(job);
      if (fg) {
        foreground++;
      } else {
        background++;
      }
      unawaited(() async {
        try {
          job.completer.complete(await job.work());
        } catch (e, st) {
          job.completer.completeError(e, st);
        } finally {
          _jobs.remove(job.key);
          if (fg) {
            foreground--;
          } else {
            background--;
          }
          drain();
        }
      }());
    }
  }
}

class ArtworkRepository extends CacheManager with ImageCacheManager {
  static final queue = ArtworkQueue();
  static final _demands = <String, Map<Object, ArtworkPriority>>{};
  static final instance = ArtworkRepository._();
  // Reuse the existing CachedNetworkImage disk store, not a second cache directory.
  @visibleForTesting
  ArtworkRepository.forTesting(super.config);
  ArtworkRepository._()
    : super(
        Config(DefaultCacheManager.key, fileService: ArtworkHttpFileService()),
      );
  static void demand(String url, Object owner, ArtworkPriority priority) {
    (_demands[url] ??= {})[owner] = priority;
    queue.drain();
  }

  static void release(String url, Object owner) {
    _demands[url]?.remove(owner);
    if (_demands[url]?.isEmpty ?? false) _demands.remove(url);
    queue.drain();
  }

  static ArtworkPriority priority(String url) {
    final values = _demands[url]?.values;
    return values == null || values.isEmpty
        ? ArtworkPriority.nearVisible
        : values.reduce((a, b) => a.index < b.index ? a : b);
  }

  static bool wanted(String url) =>
      !BrowsingModeSettings.instance.lite &&
      (_demands[url]?.isNotEmpty ?? false);

  /// Preserve complete identity (including auth/signed query) in cache keys. No account-crossing normalization.
  static String cacheKey(String url) => url;
  static String variant(String url, ArtworkKind kind) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host != 'image.tmdb.org' ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty ||
        uri.path.endsWith('.svg')) {
      return url;
    }
    final width = switch (kind) {
      ArtworkKind.poster => 'w185',
      ArtworkKind.cast => 'w185',
      ArtworkKind.episode => 'w300',
      ArtworkKind.backdrop => 'w1280',
      ArtworkKind.logo => 'w500',
    };
    return uri
        .replace(
          path: uri.path.replaceFirst(
            RegExp(r'^/t/p/(original|w\d+|h\d+)/'),
            '/t/p/$width/',
          ),
        )
        .toString();
  }

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final watch = Stopwatch()..start();
    return super
        .getFileStream(
          url,
          key: key,
          headers: headers,
          withProgress: withProgress,
        )
        .map((event) {
          if (event is FileInfo) {
            if (ArtworkMetrics.enabled) {
              if (ArtworkMetrics.fileReadyUs.length >= 2000) {
                ArtworkMetrics.fileReadyUs.remove(
                  ArtworkMetrics.fileReadyUs.keys.first,
                );
              }
              ArtworkMetrics.fileReadyUs[ArtworkMetrics.id(url)] =
                  DateTime.now().microsecondsSinceEpoch;
            }
            ArtworkMetrics.record(
              'file_ready',
              url: url,
              values: {
                'source': event.source.name,
                'elapsed_ms': watch.elapsedMilliseconds,
              },
            );
          }
          return event;
        });
  }
}

class ArtworkHttpFileService extends FileService {
  static int _requestId = 0;
  final http.Client client;
  final Duration requestDeadline;
  ArtworkHttpFileService({
    http.Client? client,
    this.requestDeadline = const Duration(seconds: 30),
  }) : client = client ?? http.Client() {
    concurrentFetches = 32;
  }
  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) {
    final response = Completer<FileServiceResponse>();
    final queued = Stopwatch()..start();
    unawaited(
      ArtworkRepository.queue
          .run<void>(
            'transport:${_requestId++}:$url',
            () async {
              if (!ArtworkRepository.wanted(url)) {
                throw const ArtworkCancelled();
              }
              final watch = Stopwatch()..start();
              ArtworkMetrics.record(
                'http_start',
                url: url,
                values: {
                  'queue_ms': queued.elapsedMilliseconds,
                  'priority': ArtworkRepository.priority(url).name,
                },
              );
              final abort = Completer<void>();
              final deadline = Timer(requestDeadline, () {
                if (!abort.isCompleted) abort.complete();
              });
              try {
                final request = http.AbortableRequest(
                  'GET',
                  Uri.parse(url),
                  abortTrigger: abort.future,
                );
                if (headers != null) request.headers.addAll(headers);
                final original = HttpGetResponse(await client.send(request));
                final done = Completer<void>();
                final measured = _MeasuredResponse(original, url, watch, done);
                response.complete(measured);
                if (original.statusCode != 200 && original.statusCode != 202) {
                  await measured.content.drain<void>();
                }
                await done.future;
              } finally {
                deadline.cancel();
              }
            },
            priority: () => ArtworkRepository.priority(url),
            wanted: () => ArtworkRepository.wanted(url),
          )
          .catchError((Object e, StackTrace st) {
            if (!response.isCompleted) response.completeError(e, st);
            ArtworkMetrics.record(
              e is ArtworkCancelled ? 'cancelled' : 'http_error',
              url: url,
            );
          }),
    );
    return response.future;
  }
}

class _MeasuredResponse implements FileServiceResponse {
  final FileServiceResponse original;
  final String url;
  final Stopwatch watch;
  final Completer<void> done;
  _MeasuredResponse(this.original, this.url, this.watch, this.done);
  @override
  Stream<List<int>> get content async* {
    var bytes = 0;
    var complete = false;
    try {
      await for (final chunk in original.content.timeout(
        const Duration(seconds: 30),
      )) {
        bytes += chunk.length;
        yield chunk;
      }
      complete = true;
    } finally {
      ArtworkMetrics.record(
        'http_end',
        url: url,
        values: {
          'body_bytes': bytes,
          'complete': complete,
          'download_ms': watch.elapsedMilliseconds,
          'status': statusCode,
        },
      );
      if (!done.isCompleted) done.complete();
    }
  }

  @override
  int? get contentLength => original.contentLength;
  @override
  int get statusCode => original.statusCode;
  @override
  DateTime get validTill => original.validTill;
  @override
  String? get eTag => original.eTag;
  @override
  String get fileExtension => original.fileExtension;
}
