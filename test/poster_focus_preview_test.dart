import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/application/browsing_mode.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/poster_focus_preview.dart';
import 'package:iptv_flutter/presentation/series_catalog_screen.dart';
import 'package:iptv_flutter/presentation/details_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'movie_catalog_screen_test.dart' show MovieProvider;

Future<void> mount(
  WidgetTester tester,
  PosterPreviewController controller,
  List<FocusNode> nodes, {
  ScrollController? scroll,
  VoidCallback? onOpen,
  bool reduced = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduced,
        ),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(80, 70, 12, 12),
            child: GridView.count(
              controller: scroll,
              crossAxisCount: 3,
              childAspectRatio: .8,
              children: List.generate(
                nodes.length,
                (i) => PosterPreviewAnchor(
                  key: ValueKey('anchor-$i'),
                  controller: controller,
                  item: ContentItem(
                    id: '$i',
                    name: 'Movie $i',
                    type: ContentType.movies,
                    releaseYear: 2026,
                  ),
                  focusNode: nodes[i],
                  poster: const ColoredBox(color: Colors.blueGrey),
                  onPlay: onOpen ?? () {},
                  onDetails: onOpen ?? () {},
                  myListAction: const Icon(Icons.add),
                  cardBuilder: (node) => TextButton(
                    focusNode: node,
                    onPressed: onOpen ?? () {},
                    child: Text('Poster $i'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => BrowsingModeSettings.instance.mode = BrowsingMode.premium);
  testWidgets(
    'one floating preview, cancellable dwell, immediate OK and Back restores poster focus',
    (tester) async {
      final controller = PosterPreviewController();
      final nodes = List.generate(6, (_) => FocusNode());
      var opens = 0;
      await mount(tester, controller, nodes, onOpen: () => opens++);
      final before = tester.getRect(find.byKey(const ValueKey('anchor-0')));
      nodes[0].requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsOneWidget,
      );
      expect(find.text('Details'), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('anchor-0'))), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opens, 1);
      nodes[1].requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Details'), findsNothing);
      nodes[2].requestFocus();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 460));
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsOneWidget,
      );
      expect(find.text('Movie 2'), findsOneWidget);
      expect(find.text('Movie 0'), findsNothing);
      expect(find.text('Details'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'poster preview play',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.active, isFalse);
      expect(nodes[2].hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
  testWidgets(
    'edge previews remain within viewport and scrolling/disposal removes them',
    (tester) async {
      final controller = PosterPreviewController(), scroll = ScrollController();
      final nodes = List.generate(24, (_) => FocusNode());
      await mount(tester, controller, nodes, scroll: scroll);
      for (final i in [0, 2, 5]) {
        nodes[i].requestFocus();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final rect = tester.getRect(
          find.byKey(const ValueKey('floating-poster-preview')),
        );
        expect(rect.left, greaterThanOrEqualTo(79));
        expect(rect.right, lessThanOrEqualTo(789));
        expect(rect.top, greaterThanOrEqualTo(69));
        expect(rect.bottom, lessThanOrEqualTo(589));
        controller.dismiss();
        await tester.pumpAndSettle();
      }
      nodes[0].requestFocus();
      nodes[1].requestFocus();
      await tester.pumpAndSettle();
      expect(controller.active, isTrue);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(controller.active, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      controller.dispose();
      scroll.dispose();
      for (final node in nodes) {
        node.dispose();
      }
    },
  );
  testWidgets('Lite never creates the preview', (tester) async {
    BrowsingModeSettings.instance.mode = BrowsingMode.lite;
    final controller = PosterPreviewController(), node = FocusNode();
    await mount(tester, controller, [node]);
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.active, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    node.dispose();
    BrowsingModeSettings.instance.mode = BrowsingMode.premium;
  });
  testWidgets(
    'Movies grid loads focused information once, opens details and restores the exact poster',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = MovieProvider();
      final key = GlobalKey<SeriesCatalogScreenState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeriesCatalogScreen(
              key: key,
              type: ContentType.movies,
              provider: provider,
              onNavigation: () {},
              onSettings: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All Movies').last);
      await tester.pumpAndSettle();
      key.currentState!.gridFirst.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final original = FocusManager.instance.primaryFocus;
      final metadataCalls = provider.movieDetails;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(provider.movieDetails, lessThanOrEqualTo(metadataCalls + 1));
      expect(find.text('Movie synopsis'), findsOneWidget);
      final loadedCalls = provider.movieDetails;
      await tester.pump(const Duration(milliseconds: 600));
      expect(provider.movieDetails, loadedCalls);
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsNothing,
      );
      expect(key.currentState!.grid, isTrue);
      expect(FocusManager.instance.primaryFocus, same(original));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(DetailsScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('floating-poster-preview')),
        findsNothing,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(original));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets('reduced motion retains an outline without zoom', (tester) async {
    final controller = PosterPreviewController(), node = FocusNode();
    await mount(tester, controller, [node], reduced: true);
    final rect = tester.getRect(find.byKey(const ValueKey('anchor-0')));
    node.requestFocus();
    await tester.pumpAndSettle();
    final preview = tester.getSize(
      find.byKey(const ValueKey('floating-poster-preview')),
    );
    expect(preview.width, rect.width);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    node.dispose();
    expect(tester.takeException(), isNull);
  });
}
