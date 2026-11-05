# Lite browsing mode

Enable **Settings > Appearance and browsing > Browsing Mode > Lite**. Premium remains the default.

## Scope

The device-wide `browsing_mode` preference uses the existing FlutterSecureStorage dependency. It is loaded before the first app frame and remains independent of account/profile appearance preferences. Changing it updates mounted catalog, details, search and dashboard screens without reconnecting the provider.

Lite mode renders a single lazy text list for Movies and Series. It shares provider IDs, category restrictions, search, sort, watch history and My List. Continue Watching and My List are available through catalog header filters; the dashboard also renders Continue Watching as text rows. Movie details offer Play or Resume, restart and My List. Series details reuse provider seasons/episodes and stored per-episode progress.

No movie/series poster, backdrop, cast image or episode-thumbnail widgets are constructed in Lite browsing. Premium artwork trees are unmounted when switching; queued artwork warming checks the preference before starting. Existing image caches are preserved. Downloads already in flight before switching may finish in the image cache.

The existing player, stream URLs, quality, subtitles, audio, resume and Next Episode logic remain shared. Live TV and profile selection remain unchanged.

## Components

- `application/browsing_mode.dart`: device preference and notifications.
- `application/recent_catalog_cache.dart`: full and recent metadata futures scoped to each connected provider; shared with catalog/search and cleared together.
- `presentation/lite_media_list.dart`: lazy fixed-extent text rows and explicit remote traversal.
- `presentation/lite_details.dart`: text metadata, movie actions and series season/episode browsing.
- Existing settings, shared Movies/Series catalog, details router, search and dashboard choose the active presentation without retaining an inactive Premium tree.
- `presentation/artwork_prefetch.dart` skips new work in Lite mode.

Catalog caches are in-memory, matching the existing cache architecture. They are not a new offline database. Provider refresh/error/reconnection still governs when metadata is fetched. No synthetic pagination parameters are sent. Provider catalog parsing already occurs off the UI isolate for Xtream responses.

## Validation

`test/lite_mode_test.dart` covers preference persistence/defaults, settings interaction and profile independence, text catalogs/details, search, categories/sort, saved lists, restrictions, resume/restart, seasons/episodes, dashboard artwork suppression, mode switching without repeated catalog fetch, provider cache isolation and lazy traversal of 5,000 titles (fewer than 30 mounted rows in the tested viewport).

Premium catalog/details, My List, dashboard and VOD/Live TV player regression tests were exercised. Flutter analysis is clean. A separate category-PIN remote-focus test fails independently; the category-lock settings screen was not changed for Lite mode.

Fire TV memory, frame timing and cold-start speed have not been measured. The code is not automatically deployed by enabling this feature in the source.

## Manual TV checks

1. Select Lite, restart, and confirm the preference is restored.
2. Browse Movies and Series, filter categories, search, sort, open details and return to the same title.
3. Verify movie Resume/restart and series season selection/episode resume/Next Episode.
4. Add/remove My List entries and verify profile restrictions.
5. Switch back to Premium and confirm category/query/sort and cached artwork remain available.
6. Confirm Live TV playback/navigation is unaffected.
