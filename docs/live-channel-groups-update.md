# Live channel groups update

## Behavior

Add to My List uses a dark blue dialog with whole-row remote focus, General Favorites, custom group checkboxes, a custom-group count, and Save to My List. All Favorites is the computed union, not an editable membership. Cancel/Back discards membership edits. Creating a group persists the empty group and selects it in the draft without saving other membership edits.

The channel drawer has All Channels and My List primary modes. Provider categories stay in All Channels. My List shows All Favorites, custom groups, Create New Group and Manage Groups. Existing EPG, playing indicators and channel logos remain; browsing focus does not tune a stream. The header options menu exposes membership actions without requiring a long press. Hold OK and keyboard context-menu/F10 also expose actions.

Manage Groups supports create, rename, confirmed delete, group ordering and independent channel ordering. Select Move Group or Reorder Channels, press OK on a row to begin moving, Up/Down to move it, OK to save, or Back to cancel the move. Another Back closes the ordering dialog. Removed memberships are removed from that group's order; newly added memberships append. Focus is restored by stable IDs and the lists scroll focused rows into view.

## Persistence and compatibility

The existing profile-scoped secure-storage keys and group IDs are retained. The existing group JSON gains an optional `general` map. An absent entry means a legacy saved favorite remains in General Favorites. Explicit false allows membership only in custom groups. All Favorites filters the existing saved index by General/custom membership, avoiding duplicates. Deleting a group preserves other memberships and General Favorites; channels saved only in the deleted group leave the computed union.

Membership writes use the existing serialized mutation path and an additional profile-scoped rollback journal containing previous raw group/list values. Failed writes roll back; an interrupted transaction is recovered before loading either collection on restart. Storage failure during rollback leaves the journal for restart recovery. No playlist, authentication, video engine, artwork cache or playback lifecycle changes are involved.

## Files

Modified production files:
- lib/application/live_favourite_groups.dart
- lib/application/my_list.dart
- lib/presentation/live_favourite_dialogs.dart
- lib/presentation/live_channel_browser.dart
- lib/presentation/live_my_list_panel.dart (also fixes a Future-returning setState callback)

New production file: lib/presentation/live_group_manager.dart.

Tests modified: live_channel_browser_test.dart, live_favourite_dialogs_test.dart, live_my_list_groups_ui_test.dart. New test: live_membership_transaction_test.dart. Existing live_favourite_groups_test.dart and live_multiview_test.dart also run.

## Validation

Flutter analysis: no issues. Focused tests cover membership cancellation/save, new group cancellation, duplicate names, data compatibility, profile isolation, union semantics, independent order persistence, Move Mode cancel/commit, drawer focus, and unchanged playback surfaces/Multi View. The final focused run passed 24 tests, including persistence-failure rollback.

Full suite: 312 passed, 37 failed. Failures include existing profile/connection chooser expectations, catalog card layouts, My List button finders, autoplay/player control expectations and drawer sizes. These are outside the passing focused group suite; no clean baseline checkout was run, so they are not all independently proven pre-existing. Full output: Windows temp groups-full-suite.log.

Physical Fire TV testing is still required: long press versus short press, all directional routes, large group scroll restoration, restart persistence, Premium/Lite layouts and live EPG/Multi View continuity on device. No device installation or launch was performed for this task.
