import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/presentation/episode_artwork.dart';

const info = MediaDetails(
  item: ContentItem(
    id: 'tlou',
    name: 'The Last of Us',
    type: ContentType.series,
  ),
  synopsis: '',
  tmdbId: 100088,
);
Episode episode(int number, {Uri? artwork}) => Episode(
  id: 'ep$number',
  title: 'Episode',
  season: 1,
  number: number,
  extension: 'mp4',
  artwork: artwork,
);
void main() {
  test(
    'visible episodes share one season request and match episode numbers',
    () async {
      var calls = 0;
      final service = TmdbArtworkService(
        persist: false,
        client: TmdbCastService(
          persist: false,
          fetch: (uri) async {
            calls++;
            expect(uri.path, '/3/tv/100088/season/1');
            return {
              'episodes': [
                {'episode_number': 1, 'still_path': '/one.jpg'},
                {'episode_number': 2, 'still_path': '/two.jpg'},
                {'episode_number': 3, 'still_path': null},
              ],
            };
          },
        ),
      );
      final images = await Future.wait([
        service.episodeStill(info, episode(2)),
        service.episodeStill(info, episode(1)),
        service.episodeStill(info, episode(3)),
      ]);
      expect(images[0]!.path, '/t/p/w500/two.jpg');
      expect(images[1]!.path, '/t/p/w500/one.jpg');
      expect(images[2], isNull);
      await service.episodeStill(info, episode(1));
      expect(calls, 1);
    },
  );
  for (final broken in [false, true]) {
    testWidgets(
      'missing or failed provider thumbnail uses the matching TMDB still ($broken)',
      (tester) async {
        final service = TmdbArtworkService(
          persist: false,
          client: TmdbCastService(
            persist: false,
            fetch: (_) async => {
              'episodes': [
                {'episode_number': 1, 'still_path': '/one.jpg'},
              ],
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 280,
              height: 160,
              child: EpisodeArtwork(
                info: info,
                episode: episode(
                  1,
                  artwork: broken
                      ? Uri.parse('https://example.com/broken-episode.jpg')
                      : null,
                ),
                service: service,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (broken) {
          // Simulate an explicit provider failure; elapsed time alone must not race a fallback.
          final image = tester.widget<CachedNetworkImage>(
            find.byType(CachedNetworkImage).first,
          );
          final fallback = image.errorWidget!(
            tester.element(find.byType(CachedNetworkImage).first),
            'unused',
            Exception(),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: SizedBox(width: 280, height: 160, child: fallback),
            ),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.byWidgetPredicate(
            (w) => w is CachedNetworkImage && w.imageUrl.endsWith('/one.jpg'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('unavailable episode still falls back to the series backdrop', (
    tester,
  ) async {
    final service = TmdbArtworkService(
      persist: false,
      client: TmdbCastService(
        persist: false,
        fetch: (_) async => {'episodes': []},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 280,
          height: 160,
          child: EpisodeArtwork(
            info: info,
            episode: episode(1),
            backdrop: Uri.parse('https://example.com/backdrop.jpg'),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is CachedNetworkImage && w.imageUrl.endsWith('/backdrop.jpg'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
