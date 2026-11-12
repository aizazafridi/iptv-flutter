import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/profile_artwork_warmup.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/domain/trailer_movie.dart';
import 'package:iptv_flutter/data/trailers_repository.dart';
import 'package:iptv_flutter/data/artwork_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => BrowsingModeSettings.instance.mode = BrowsingMode.premium);
  test(
    'trailer warmup loads each category and deduplicates display artwork',
    () async {
      final collections = <TrailerCollection>[];
      final urls = <String>[];
      const movie = TrailerMovie(
        id: 1,
        title: 'Trailer',
        backdropPath: '/image.jpg',
      );
      await warmTrailerArtwork(
        loadPage: (collection) async {
          collections.add(collection);
          return TrailerPage([movie, movie], 1, 1);
        },
        cacheImage: (url) async => urls.add(url),
      );
      expect(collections, TrailerCollection.values);
      expect(urls.toSet(), {
        ArtworkRepository.variant(movie.card.toString(), ArtworkKind.episode),
        ArtworkRepository.variant(
          movie.backdrop.toString(),
          ArtworkKind.backdrop,
        ),
      });
      expect(urls.length, 2);
    },
  );
  test(
    'trailer warmup skips Lite and stops downloads after its budget',
    () async {
      var calls = 0;
      final pending = Completer<TrailerPage>();
      Future<TrailerPage> load(TrailerCollection _) {
        calls++;
        return pending.future;
      }

      BrowsingModeSettings.instance.mode = BrowsingMode.lite;
      await warmTrailerArtwork(loadPage: load);
      expect(calls, 0);
      BrowsingModeSettings.instance.mode = BrowsingMode.premium;
      final urls = <String>[];
      await warmTrailerArtwork(
        budget: const Duration(milliseconds: 10),
        loadPage: load,
        cacheImage: (url) async => urls.add(url),
      );
      pending.complete(
        TrailerPage(
          [const TrailerMovie(id: 1, title: 'Late', backdropPath: '/late.jpg')],
          1,
          1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(urls, isEmpty);
    },
  );
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
