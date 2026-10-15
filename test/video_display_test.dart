import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/playback/video_display.dart';
import 'package:iptv_flutter/presentation/video_display_dialog.dart';

class DisplayEngine implements VideoDisplayEngine {
  @override
  VideoDisplay videoDisplay = const VideoDisplay();
  @override
  void setVideoDisplay(VideoDisplay display) {
    videoDisplay = display;
  }
}

void main() {
  testWidgets('aspect ratio applies selected dimensions', (tester) async {
    final engine = DisplayEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoDisplayDialog(engine: engine)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('16:9'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.aspectRatio, 16 / 9);
  });
  testWidgets('zoom in, out and reset apply to video', (tester) async {
    final engine = DisplayEngine();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoDisplayDialog(engine: engine, zoom: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.zoom, closeTo(1.1, 0.001));
    await tester.tap(find.byTooltip('Move right'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move up'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.pan, const Offset(-0.05, 0.05));
    expect(engine.videoDisplay.zoom, closeTo(1.1, 0.001));
    await tester.tap(find.byTooltip('Center video'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.pan, Offset.zero);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.zoom, closeTo(1, 0.001));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset zoom'));
    await tester.pumpAndSettle();
    expect(engine.videoDisplay.zoom, 1);
  });
}
