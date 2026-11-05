import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/profile_artwork_warmup.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => BrowsingModeSettings.instance.mode = BrowsingMode.premium);
  test('startup uses shared poster variants and deduplicates URLs', () async {
    final calls = <String>[];
    final item = ContentItem(
      id: '1',
      name: 'Title',
      type: ContentType.movies,
      artwork: Uri.parse('https://image.tmdb.org/t/p/original/poster.jpg'),
    );
    await warmProfileArtwork(
      [item, item],
      cacheImage: (url) async {
        calls.add(url);
      },
    );
    expect(calls, ['https://image.tmdb.org/t/p/w185/poster.jpg']);
  });
  test('Lite performs neither metadata nor image requests', () async {
    BrowsingModeSettings.instance.mode = BrowsingMode.lite;
    var calls = 0;
    await warmProfileArtwork(
      [const ContentItem(id: '1', name: 'Title', type: ContentType.series)],
      resolvePoster: (_) async {
        calls++;
        return null;
      },
      cacheImage: (_) async {
        calls++;
      },
    );
    expect(calls, 0);
  });
  test(
    'login budget does not wait for slow metadata or start obsolete downloads',
    () async {
      final pending = Completer<Uri?>();
      var downloads = 0;
      await warmProfileArtwork(
        [const ContentItem(id: '1', name: 'Title', type: ContentType.series)],
        budget: const Duration(milliseconds: 10),
        resolvePoster: (_) => pending.future,
        cacheImage: (_) async {
          downloads++;
        },
      );
      pending.complete(Uri.parse('https://example.com/poster.jpg'));
      await Future<void>.delayed(Duration.zero);
      expect(downloads, 0);
    },
  );
  test('startup keeps no more than four image jobs active', () async {
    var active = 0, peak = 0;
    final items = List.generate(
      12,
      (i) => ContentItem(
        id: '$i',
        name: '$i',
        type: ContentType.movies,
        artwork: Uri.parse('https://example.com/$i.jpg'),
      ),
    );
    await warmProfileArtwork(
      items,
      cacheImage: (_) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
      },
    );
    expect(peak, 4);
    expect(active, 0);
  });
}
