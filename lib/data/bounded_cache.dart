import 'dart:collection';

/// Keeps recently used metadata without retaining an entire browsing session.
class BoundedCache<K, V extends Object> extends MapBase<K, V> {
  final int capacity;
  final _entries = <K, V>{};

  BoundedCache(this.capacity) : assert(capacity > 0);

  @override
  V? operator [](Object? key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key as K] = value;
    return value;
  }

  @override
  void operator []=(K key, V value) {
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
  }

  @override
  Iterable<K> get keys => _entries.keys;

  @override
  bool containsKey(Object? key) => _entries.containsKey(key);

  @override
  V? remove(Object? key) => _entries.remove(key);

  @override
  void clear() => _entries.clear();
}
