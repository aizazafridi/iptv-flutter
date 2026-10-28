import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/continue_watching_artwork.dart';

void main() {
  testWidgets('missing backdrop displays whole poster with contain fit', (
    tester,
  ) async {
    final service = TmdbArtworkService(
      client: TmdbCastService(),
      persist: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 212,
          height: 86,
          child: ContinueWatchingArtwork(
            service: service,
            item: ContentItem(
              id: '1',
              name: 'Movie',
              type: ContentType.movies,
              artwork: Uri.parse('https://example.com/poster.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.fit, BoxFit.contain);
    expect(image.imageUrl, 'https://example.com/poster.jpg');
    await tester.pumpWidget(const SizedBox());
  });
}
