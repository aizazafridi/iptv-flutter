import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/data/subtitle_service.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/subtitle_dialog.dart';
import 'subtitle_test.dart' show FakeEngine;

class SearchService extends SubtitleService {
  SearchService() : super('fixture');
  final searches = <(String, String)>[];
  final downloads = <int>[];
  bool fail = false;
  Completer<Uri>? pending;
  List<SubtitleResult> rows = const [
    SubtitleResult(
      1,
      'The.Voyeurs.2021.1080p.AMZN.WEB-DL.DDP5.1.H.264-CMRG \u00b7 en',
      score: 2,
    ),
    SubtitleResult(2, 'The.Voyeurs.2021.720p.WEBRip \u00b7 en', score: 10),
  ];
  @override
  Future<List<SubtitleResult>> search(String title, String language) async {
    searches.add((title, language));
    return rows;
  }

  @override
  Future<Uri> download(SubtitleResult result) async {
    downloads.add(result.fileId);
    if (fail) {
      throw const ProviderException('Download unavailable. Please retry.');
    }
    return pending == null
        ? Uri.parse('https://example.com/subtitle.srt')
        : pending!.future;
  }
}

class SubtitleEngine extends FakeEngine {
  final loaded = <Uri>[];
  bool reject = false;
  @override
  Future<void> addSubtitle(Uri uri) async {
    if (reject) throw const ProviderException('Subtitle could not be loaded.');
    loaded.add(uri);
  }
}

Future<void> mount(
  WidgetTester tester,
  SearchService service,
  SubtitleEngine engine, {
  int? selected,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => OnlineSubtitleDialog(
                title: 'The Voyeurs (2021)',
                engine: engine,
                service: service,
                selectedFileId: selected,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'release formatting cleans the title while retaining the full original filename',
    () {
      const filename = 'The.Voyeurs.2021.1080p.AMZN.WEB-DL.DDP5.1.H.264-CMRG';
      const result = SubtitleResult(
        7,
        '$filename \u00b7 en',
        fileName: filename,
      );
      final display = subtitleResultDisplay(result);
      expect(display.title, 'The Voyeurs \u00b7 2021 \u00b7 1080p');
      expect(display.details, contains('AMZN WEB-DL'));
      expect(display.details, contains('English'));
      expect(result.fileName, filename);
      expect(result.label, '$filename \u00b7 en');
    },
  );
  testWidgets(
    'preference failures retain the loaded checkmark and retry without downloading again',
    (tester) async {
      final service = SearchService();
      final engine = SubtitleEngine();
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => OnlineSubtitleDialog(
                    title: 'The Voyeurs',
                    engine: engine,
                    service: service,
                    onSelected: (_) async {
                      saves++;
                      if (saves == 1) {
                        throw const ProviderException('Storage unavailable');
                      }
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Subtitle loaded, but its preference'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(engine.loaded, hasLength(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.downloads, [2]);
      expect(engine.loaded, hasLength(1));
      expect(saves, 2);
      expect(find.byType(OnlineSubtitleDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'best match far down the list receives remote focus without loading',
    (tester) async {
      final service = SearchService()
        ..rows = List.generate(
          30,
          (i) =>
              SubtitleResult(i, 'Title.2021.1080p.WEB-DL', score: i.toDouble()),
        );
      final engine = SubtitleEngine();
      await mount(tester, service, engine);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'online subtitle 29',
      );
      expect(service.downloads, isEmpty);
      expect(engine.loaded, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'online subtitle 28',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets(
      'centered compact search focuses best result without applying at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = SearchService();
        final engine = SubtitleEngine();
        await mount(tester, service, engine, selected: 1);
        expect(find.text('Find Subtitles'), findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'online subtitle 2',
        );
        expect(service.downloads, isEmpty);
        expect(engine.loaded, isEmpty);
        final bounds = tester.getRect(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(bounds.width, inInclusiveRange(520, 600));
        expect(bounds.center.dx, closeTo(size.width / 2, 1));
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.text(service.rows.first.label), findsNothing);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus!.debugLabel,
          'online subtitle 1',
        );
        expect(engine.loaded, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(OnlineSubtitleDialog), findsNothing);
        expect(engine.loaded, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'current title stays fixed while language changes for Search Again',
    (tester) async {
      final service = SearchService();
      final engine = SubtitleEngine();
      await mount(tester, service, engine);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Search title'), findsNothing);
      await tester.tap(find.text('English').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search Again'));
      await tester.pumpAndSettle();
      expect(service.searches.last, ('The Voyeurs (2021)', 'es'));
      expect(service.downloads, isEmpty);
      expect(
        FocusManager.instance.primaryFocus!.debugLabel,
        'online subtitle 2',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('download and engine loading complete before the dialog closes', (
    tester,
  ) async {
    final service = SearchService()..pending = Completer<Uri>();
    final engine = SubtitleEngine();
    await mount(tester, service, engine);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byType(OnlineSubtitleDialog), findsOneWidget);
    expect(engine.loaded, isEmpty);
    expect(find.textContaining('Downloading and loading'), findsOneWidget);
    service.pending!.complete(Uri.parse('https://example.com/subtitle.srt'));
    await tester.pumpAndSettle();
    expect(engine.loaded, hasLength(1));
    expect(service.downloads, [2]);
    expect(find.byType(OnlineSubtitleDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('download failures keep the dialog open for retry', (
    tester,
  ) async {
    final service = SearchService()..fail = true;
    final engine = SubtitleEngine();
    await mount(tester, service, engine);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load subtitle'), findsOneWidget);
    expect(engine.loaded, isEmpty);
    service.fail = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(engine.loaded, hasLength(1));
    expect(find.byType(OnlineSubtitleDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Back during download discards the result without changing the loaded subtitle',
    (tester) async {
      final service = SearchService()..pending = Completer<Uri>();
      final engine = SubtitleEngine();
      await mount(tester, service, engine);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      service.pending!.complete(Uri.parse('https://example.com/subtitle.srt'));
      await tester.pumpAndSettle();
      expect(engine.loaded, isEmpty);
      expect(find.byType(OnlineSubtitleDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'engine rejection shows an error instead of assuming the subtitle loaded',
    (tester) async {
      final service = SearchService();
      final engine = SubtitleEngine()..reject = true;
      await mount(tester, service, engine);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(OnlineSubtitleDialog), findsOneWidget);
      expect(engine.loaded, isEmpty);
      expect(find.textContaining('Could not load subtitle'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
