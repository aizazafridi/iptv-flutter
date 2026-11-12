import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../domain/iptv_provider.dart';
import '../domain/models.dart';
import '../domain/trailer_movie.dart';
import 'watch_history.dart';
import 'category_locks.dart';
import 'trailer_catalog_match.dart';

class TrailerNotice {
  final String event;
  final TrailerMovie movie;
  final bool read;
  const TrailerNotice(this.event, this.movie, {this.read = false});
  bool get available => event.startsWith('available:');
  String get message => available
      ? '${movie.title} is now available in your library.'
      : '${movie.title} is scheduled for release on ${movie.dateLabel}.';
}

class TrailerReminders extends ChangeNotifier {
  static final _instances = Expando<TrailerReminders>();
  static TrailerReminders forProvider(IptvProvider p) =>
      _instances[p] ??= TrailerReminders(WatchHistory.forProvider(p).scope);
  final String scope;
  final FlutterSecureStorage storage;
  final DateTime Function() clock;
  TrailerReminders(
    this.scope, {
    this.storage = const FlutterSecureStorage(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  List<TrailerMovie> _items = [];
  List<TrailerMovie> get items => List.unmodifiable(_items);
  final _preferences = <int, ({bool release, bool availability})>{};
  final _events = <String>{};
  final _notices = <TrailerNotice>[];
  List<TrailerNotice> get notices => List.unmodifiable(_notices.reversed);
  int get unread => _notices.where((n) => !n.read).length;
  bool contains(int id) => _items.any((m) => m.id == id);
  ({bool release, bool availability}) preferences(int id) =>
      _preferences[id] ?? (release: true, availability: true);
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> load() => _loading ??= () async {
    try {
      final raw = await storage.read(key: 'trailer_reminders:$scope');
      if (raw != null) {
        final data = jsonDecode(raw);
        final rows = data is List ? data : data['items'] as List;
        _items = rows
            .whereType<Map>()
            .map((r) => TrailerMovie.fromJson(Map<String, dynamic>.from(r)))
            .toList();
        if (data is Map) {
          for (final entry in (data['preferences'] as Map? ?? {}).entries) {
            _preferences[int.parse(entry.key)] = (
              release: entry.value['release'] == true,
              availability: entry.value['availability'] == true,
            );
          }
          _events.addAll((data['events'] as List? ?? []).cast<String>());
          for (final row in data['notices'] as List? ?? []) {
            _notices.add(
              TrailerNotice(
                row['event'],
                TrailerMovie.fromJson(Map<String, dynamic>.from(row['movie'])),
                read: row['read'] == true,
              ),
            );
          }
        }
      }
      notifyListeners();
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }();
  String encode() => jsonEncode({
    'items': _items.map((m) => m.toJson()).toList(),
    'preferences': {
      for (final e in _preferences.entries)
        '${e.key}': {
          'release': e.value.release,
          'availability': e.value.availability,
        },
    },
    'events': _events.toList(),
    'notices': [
      for (final n in _notices)
        {'event': n.event, 'movie': n.movie.toJson(), 'read': n.read},
    ],
  });
  Future<void> change(void Function() action) async {
    await load();
    final work = _writes.then((_) async {
      final items = List<TrailerMovie>.of(_items);
      final prefs = Map.of(_preferences);
      final events = Set<String>.of(_events);
      final notices = List<TrailerNotice>.of(_notices);
      action();
      try {
        await storage.write(key: 'trailer_reminders:$scope', value: encode());
      } catch (_) {
        _items = items;
        _preferences
          ..clear()
          ..addAll(prefs);
        _events
          ..clear()
          ..addAll(events);
        _notices
          ..clear()
          ..addAll(notices);
        rethrow;
      }
      notifyListeners();
    });
    _writes = work.catchError((_) {});
    await work;
  }

  Future<void> toggle(TrailerMovie movie) => change(() {
    if (contains(movie.id)) {
      _items.removeWhere((m) => m.id == movie.id);
      _preferences.remove(movie.id);
    } else {
      _items.insert(0, movie);
      final now = clock();
      _preferences[movie.id] = (
        release:
            movie.release != null &&
            !movie.release!.isBefore(DateTime(now.year, now.month, now.day)),
        availability: true,
      );
    }
  });
  Future<void> setPreferences(
    int id, {
    required bool release,
    required bool availability,
  }) => change(() {
    if (contains(id)) {
      _preferences[id] = (release: release, availability: availability);
    }
  });
  Future<void> markRead() => change(() {
    for (var i = 0; i < _notices.length; i++) {
      _notices[i] = TrailerNotice(
        _notices[i].event,
        _notices[i].movie,
        read: true,
      );
    }
  });
  void emit(String event, TrailerMovie movie) {
    if (_events.add(event)) _notices.add(TrailerNotice(event, movie));
  }

  Future<void> checkDates() => change(() {
    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    for (final movie in _items) {
      if (preferences(movie.id).release &&
          movie.release != null &&
          !movie.release!.isAfter(today)) {
        emit('release:${movie.id}:${movie.releaseDate}', movie);
      }
    }
  });
  Future<void> checkCatalog(
    IptvProvider provider,
    List<ContentItem> catalog,
  ) async {
    await load();
    if (_items.isEmpty) return;
    final locks = CategoryLocks.forProvider(provider);
    await locks.load();
    if (locks.kidsProfile) return;
    final visible = await locks.visibleItems(
      catalog,
      excludeConfiguredLocks: true,
    );
    final ids = <int>{};
    final titles = <String, List<ContentItem>>{};
    for (final item in visible) {
      if (item.type != ContentType.movies) continue;
      if (item.tmdbId != null) ids.add(item.tmdbId!);
      titles.putIfAbsent(catalogMovieTitle(item.name), () => []).add(item);
    }
    final matches = <TrailerMovie>[];
    for (final movie in List<TrailerMovie>.of(_items)) {
      if (!preferences(movie.id).availability ||
          _events.contains('available:${movie.id}')) {
        continue;
      }
      if (ids.contains(movie.id)) {
        matches.add(movie);
        continue;
      }
      final candidates = {movie.title, movie.originalTitle}
          .where((s) => s.isNotEmpty)
          .map(catalogMovieTitle)
          .toSet()
          .expand((title) => titles[title] ?? <ContentItem>[])
          .where(
            (item) => item.tmdbId == null && trailerTitleMatches(item, movie),
          )
          .take(3);
      for (final item in candidates) {
        try {
          final details = await provider
              .getMovieDetails(item)
              .timeout(const Duration(seconds: 8));
          final reliable = details.tmdbId != null
              ? details.tmdbId == movie.id
              : trailerMetadataMatches(details, movie);
          if (reliable) {
            matches.add(movie);
            break;
          }
        } catch (_) {
          /* Try again after the next catalogue refresh. */
        }
      }
    }
    if (matches.isEmpty) return;
    await change(() {
      for (final movie in matches) {
        if (contains(movie.id) && preferences(movie.id).availability) {
          emit('available:${movie.id}', movie);
        }
      }
    });
  }
}
