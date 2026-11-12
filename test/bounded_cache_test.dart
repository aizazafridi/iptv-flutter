import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/bounded_cache.dart';

void main() {
  test('evicts least recently used metadata, including after replacement', () {
    final cache = BoundedCache<String, int>(2);
    cache['a'] = 1;
    cache['b'] = 2;
    expect(cache['a'], 1);
    cache['c'] = 3;
    expect(cache.containsKey('b'), false);
    cache['a'] = 4;
    cache['d'] = 5;
    expect(cache.containsKey('c'), false);
    expect(cache.length, 2);
    expect(cache.remove('a'), 4);
    cache.clear();
    expect(cache, isEmpty);
  });
}
