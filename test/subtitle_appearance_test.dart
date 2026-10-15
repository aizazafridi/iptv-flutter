import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/playback/subtitle_customization.dart';
import 'package:iptv_flutter/presentation/subtitle_appearance_dialog.dart';

class StyleEngine implements SubtitleCustomizationEngine {
  @override
  SubtitleAppearance subtitleAppearance = const SubtitleAppearance();
  @override
  Stream<String> get selectedSubtitle => const Stream.empty();
  @override
  void setSubtitleAppearance(SubtitleAppearance appearance) {
    subtitleAppearance = appearance;
  }

  @override
  Future<void> addNamedSubtitle(Uri uri, String name) async {}
}

void main() {
  testWidgets('subtitle appearance choices update size, color and position', (
    tester,
  ) async {
    final engine = StyleEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SubtitleAppearanceDialog(engine: engine)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();
    expect(engine.subtitleAppearance.size, 32);
    await tester.tap(find.text('White'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yellow').last);
    await tester.pumpAndSettle();
    expect(engine.subtitleAppearance.color, 'Yellow');
    await tester.tap(find.text('Bottom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top').last);
    await tester.pumpAndSettle();
    expect(engine.subtitleAppearance.alignment, Alignment.topCenter);
    expect(
      tester.widget<Text>(find.text('Subtitle preview')).style!.color,
      Colors.yellow,
    );
  });
}
