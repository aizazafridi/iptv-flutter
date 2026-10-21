import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/application/appearance.dart';
import 'package:iptv_flutter/application/category_locks.dart';
import 'package:iptv_flutter/domain/models.dart';
import 'package:iptv_flutter/presentation/player_screen.dart';
import 'package:iptv_flutter/presentation/my_list_button.dart';
import 'package:iptv_flutter/presentation/widgets.dart';
import 'package:iptv_flutter/presentation/browse_screen.dart';
import 'package:iptv_flutter/presentation/category_card_row.dart';
import 'package:iptv_flutter/presentation/category_lock_settings_screen.dart';
import 'widget_test.dart' show FakeProvider;
import 'subtitle_test.dart' show FakeEngine;

class RemoteEngine extends FakeEngine {
  int toggles = 0;
  @override
  Future<void> togglePause() async {
    toggles++;
  }
}

class ManyRowsProvider extends FakeProvider {
  @override
  Future<List<Category>> getCategories(ContentType type) async =>
      List.generate(8, (i) => Category('$i', 'Category $i', type));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'Select activates focused player controls and arrows move focus',
    (tester) async {
      final engine = RemoteEngine();
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
          },
          home: PlayerScreen(
            source: PlaybackSource(
              uri: Uri.parse('https://example.com/movie'),
              title: 'Movie',
            ),
            engineFactory: () => engine,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<IconButton>(find.byTooltip('Pause'));
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(engine.toggles, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(engine.toggles, 2);
      final focused = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNot(same(focused)));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'favourite button inside a title card is reachable with the remote',
    (tester) async {
      final provider = FakeProvider();
      final node = FocusNode();
      var opened = false;
      const item = ContentItem(
        id: '42',
        name: 'Movie',
        type: ContentType.movies,
      );
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
          },
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: FocusCard(
                  focusNode: node,
                  onTap: () => opened = true,
                  child: Row(
                    children: [
                      const Expanded(child: Text('Movie')),
                      MyListButton(provider: provider, item: item),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(MyList.forProvider(provider).contains(item), isTrue);
      expect(opened, isFalse);
      await tester.pumpWidget(const SizedBox());
      node.dispose();
      provider.dispose();
    },
  );
  testWidgets(
    'Down moves across card categories beyond the initially visible rows',
    (tester) async {
      final appearance = AppAppearance();
      await appearance.setCards(ContentType.movies, true);
      final provider = ManyRowsProvider();
      await tester.pumpWidget(
        MaterialApp(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                DirectionalFocusIntent(TraversalDirection.right),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                DirectionalFocusIntent(TraversalDirection.left),
            SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
              TraversalDirection.up,
            ),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
          },
          home: BrowseScreen(
            provider: provider,
            type: ContentType.movies,
            appearance: appearance,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<CategoryCardRow>(find.byType(CategoryCardRow).first)
          .entryFocusNode!
          .requestFocus();
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(find.text('Category 2'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        startsWith('title 5:'),
      );
      expect(find.byTooltip('Lock category'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
      appearance.dispose();
    },
  );
  testWidgets(
    'category locks can be set in Settings without controls in browsing',
    (tester) async {
      final provider = FakeProvider();
      final locks = CategoryLocks.forProvider(provider);
      await locks.setPassword('123456');
      await tester.pumpWidget(
        MaterialApp(home: CategoryLockSettingsScreen(provider: provider)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(
        locks.configured(const Category('7', 'English (4K)', ContentType.live)),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
