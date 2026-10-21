import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:iptv_flutter/application/live_favourite_groups.dart';
import 'package:iptv_flutter/application/my_list.dart';
import 'package:iptv_flutter/presentation/live_my_list_panel.dart';
import 'profiles_locks_test.dart' show CatalogFixture;
import 'live_favourite_groups_test.dart' show channels;

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'My List groups filter favourites and remote Right opens channel organization',
    (tester) async {
      final provider = CatalogFixture();
      final list = MyList.forProvider(provider);
      for (final channel in channels) {
        await list.toggle(channel);
      }
      final groups = LiveFavouriteGroups.forProvider(provider);
      final sports = await groups.create('Sports');
      await groups.assign('1', {sports});
      var selected = LiveFavouriteGroups.all;
      String? played;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => LiveMyListPanel(
                provider: provider,
                selectedGroup: selected,
                onGroupChanged: (id) => update(() => selected = id),
                onPlay: (channel) => played = channel.id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final organize = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Organize Three',
        ),
      );
      // Latest favourites appear first, so channel Three receives initial focus.
      expect(organize.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose groups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sports'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(groups.memberships('3'), {sports});
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tap(find.text('Sports (2)').last);
      await tester.pumpAndSettle();
      expect(selected, sports);
      expect(find.text('Two'), findsNothing);
      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(played, '1');
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
  testWidgets(
    'new group can be created and deleted without removing favourite channels',
    (tester) async {
      final provider = CatalogFixture();
      final list = MyList.forProvider(provider);
      await list.toggle(channels.first);
      final groups = LiveFavouriteGroups.forProvider(provider);
      var selected = LiveFavouriteGroups.all;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, update) => LiveMyListPanel(
                provider: provider,
                selectedGroup: selected,
                onGroupChanged: (id) => update(() => selected = id),
                onPlay: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('New group'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Group name',
        ),
        'News',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(groups.groups.single.name, 'News');
      await tester.tap(find.byTooltip('Manage groups'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete News'));
      await tester.pumpAndSettle();
      expect(groups.groups, isEmpty);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(await list.items(channels.first.type), hasLength(1));
      expect(find.text('One'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      provider.dispose();
    },
  );
}
