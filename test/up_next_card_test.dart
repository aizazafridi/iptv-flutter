import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/presentation/next_episode_countdown.dart';
import 'package:iptv_flutter/domain/models.dart';

void main() {
  testWidgets('preview keeps focus and countdown defers while busy', (
    tester,
  ) async {
    var plays = 0;
    var countdown = false;
    var paused = false;
    late StateSetter update;
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, set) {
            update = set;
            return Scaffold(
              body: Column(
                children: [
                  TextButton(
                    focusNode: focus,
                    autofocus: true,
                    onPressed: () {},
                    child: const Text('Controls'),
                  ),
                  NextEpisodeCountdown(
                    episode: const Episode(
                      id: '2',
                      title: 'Next',
                      season: 1,
                      number: 2,
                      extension: 'mp4',
                    ),
                    countdown: countdown,
                    paused: paused,
                    onPlay: () => plays++,
                    onCancel: () {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 40));
    expect(plays, 0);
    update(() => countdown = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    update(() => paused = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(plays, 0);
    update(() => paused = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    expect(plays, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(plays, 1);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });
}
