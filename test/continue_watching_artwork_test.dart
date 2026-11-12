import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iptv_flutter/data/tmdb_cast_service.dart';
import 'package:iptv_flutter/data/tmdb_artwork_service.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/continue_watching_artwork.dart';

void main() {
  testWidgets(
    'missing backdrop crops the poster to fill a loosely constrained card',
    (tester) async {
      final service = TmdbArtworkService(
        client: TmdbCastService(),
        persist: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 212,
              height: 86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.fit, BoxFit.cover);
      expect(
        tester.getSize(find.byType(ContinueWatchingArtwork)),
        const Size(212, 86),
      );
      expect(image.imageUrl, 'https://example.com/poster.jpg');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
