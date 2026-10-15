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
    'episode images accept alternate fields and fall back to series artwork',
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
        'https://example.com/series.jpg',
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
      await tester.tap(find.byTooltip('Episodes'));
      await tester.pumpAndSettle();
      final artwork = tester.widget<Artwork>(find.byType(Artwork));
      expect(artwork.uri, poster);
      expect(artwork.fallbackUri, poster);
      expect(find.byType(Image), findsOneWidget);
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
    final image = clip.child! as Image;
    final fallback =
        image.errorBuilder!(context, Exception('unavailable'), null) as Image;
    expect((fallback.image as NetworkImage).url, poster.toString());
    expect(
      fallback.errorBuilder!(context, Exception('unavailable'), null),
      isA<Container>(),
    );
  });
  testWidgets(
    'a stalled episode thumbnail displays the series poster before any image bytes arrive',
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
      final primary = (artwork.build(context) as ClipRRect).child! as Image;
      final loading =
          primary.frameBuilder!(context, const SizedBox(), null, false)
              as Image;
      expect((loading.image as NetworkImage).url, poster.toString());
      expect(
        loading.frameBuilder!(context, const SizedBox(), null, false),
        isA<Container>(),
      );
      const decodedFrame = SizedBox(key: ValueKey('episode-frame'));
      expect(
        primary.frameBuilder!(context, decodedFrame, 0, false),
        same(decodedFrame),
      );
    },
  );
}
