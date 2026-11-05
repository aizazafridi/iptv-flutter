import 'package:iptv_flutter/presentation/shared_artwork_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/data/xtream/xtream_provider.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/widgets.dart';
import 'provider_test.dart' show FixtureClient;
import 'subtitle_test.dart' show FakeEngine;

void main() {
  test(
    'episode images accept alternate fields and leave invalid thumbnails for UI fallback',
    () async {
      final client = FixtureClient();
      client.fixture = {
        'info': {
          'movie_image': '',
          'cover_big': '',
          'cover': 'https://example.com/series.jpg',
        },
        'episodes': {
          '1': [
            {
              'id': 1,
              'episode_num': 1,
              'info': {
                'movie_image': '',
                'cover_big': 'https://example.com/one.jpg',
              },
            },
            {
              'id': 2,
              'episode_num': 2,
              'info': [],
              'movie_image': 'https://example.com/two.jpg',
            },
            {
              'id': 3,
              'episode_num': 3,
              'info': {'movie_image': 'invalid'},
            },
          ],
        },
      };
      final provider = XtreamProvider(client);
      final series = await provider.getSeriesDetails(
        const ContentItem(id: '42', name: 'Series', type: ContentType.series),
      );
      expect(
        series.details.artwork.toString(),
        'https://example.com/series.jpg',
      );
      expect(series.episodes.map((e) => e.artwork.toString()), [
        'https://example.com/one.jpg',
        'https://example.com/two.jpg',
        'null',
      ]);
      provider.dispose();
    },
  );

  testWidgets(
    'player episode tiles receive the detailed series poster when catalog image is absent',
    (tester) async {
      const episode = Episode(
        id: '1',
        title: 'Pilot',
        season: 1,
        number: 1,
        extension: 'mp4',
      );
      final poster = Uri.parse('https://example.com/series.jpg');
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/episode'),
              title: 'Series',
            ),
            engineFactory: () => FakeEngine(),
            item: const ContentItem(
              id: '42',
              name: 'Series',
              type: ContentType.series,
            ),
            episode: episode,
            episodes: const [episode],
            seriesArtwork: poster,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Episodes'));
      await tester.pumpAndSettle();
      final images = tester.widgetList<SharedArtworkImage>(
        find.byType(SharedArtworkImage),
      );
      expect(
        images.any((image) => image.imageUrl == poster.toString()),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed episode image tries series poster before placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    final context = tester.element(find.byType(Scaffold));
    final poster = Uri.parse('https://example.com/series.jpg');
    final widget = Artwork(
      Uri.parse('https://example.com/missing.jpg'),
      fallbackUri: poster,
    );
    final clip = widget.build(context) as ClipRRect;
    final image = clip.child! as SharedArtworkImage;
    final fallback =
        image.errorWidget!(context, 'unused', Exception('unavailable'))
            as SharedArtworkImage;
    expect(fallback.imageUrl, poster.toString());
    expect(
      fallback.errorWidget!(context, 'unused', Exception('unavailable')),
      isA<Container>(),
    );
  });
  testWidgets(
    'a pending episode thumbnail uses a fixed placeholder without starting a competing poster',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final context = tester.element(find.byType(Scaffold));
      final poster = Uri.parse('https://example.com/series.jpg');
      final artwork = Artwork(
        Uri.parse('http://unreachable.example/episode.jpg'),
        fallbackUri: poster,
      );
      final primary =
          (artwork.build(context) as ClipRRect).child! as SharedArtworkImage;
      expect(primary.placeholder!(context, 'unused'), isA<Container>());
      expect(
        primary.errorWidget!(context, 'unused', Exception()),
        isA<SharedArtworkImage>(),
      );
    },
  );
}
