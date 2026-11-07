# Movies grid floating focus preview (staged rollout)

## Scope

Enabled only in the Premium Movies grid. Series, Dashboard, Continue Watching and existing catalog rails keep their prior behavior until physical Fire TV validation succeeds. Lite stays text-only. No playback engine, provider, authentication or metadata API changes are included.

## Files and architecture

- New: `lib/presentation/poster_focus_preview.dart`: one page-owned controller, overlay entry and cancellable 450 ms dwell timer. A single active overlay animation scales to 1.12 over 200 ms with easeOutCubic. Original cards retain layout/focus and become transparent while their floating representation is shown. A composited target/follower keeps the preview anchored; viewport/safe-area clamping moves it inward or places information above. Scroll checks close off-screen anchors. Reduced motion keeps the outline without zoom.
- Modified: `lib/presentation/catalog_poster_artwork.dart`: metadata-free cached preview artwork observes existing resolved poster URLs and shared image downloads.
- Modified: `lib/presentation/series_catalog_screen.dart`: Movies-grid-only integration; existing card dimensions preserved. Existing Play/Resume, Details, My List, saved data and image cache are reused. No metadata is requested for focus. Existing inline expansion remains the default elsewhere. Back dismisses the preview first; navigation closes it; the catalog restores the original focus node.
- New: `test/poster_focus_preview_test.dart`: focus/dwell/cancellation, immediate OK, actions and Back, boundaries, scroll/disposal cleanup, Lite, reduced motion, actual Movies-grid Details and exact focus restoration, and no new provider metadata requests.

The floating poster uses the same artwork component, URL variant, image dimensions and shared cache. No higher-resolution backdrop or video preview is fetched. Metadata is limited to existing catalog title, year, rating and known Resume state; missing fields are omitted.

## Validation

- Flutter analysis: no issues.
- Focused preview, Movies, Series and Lite regression suite: 41 passed.
- Full suite: 335 passed, 37 failed. No new preview test failed. Existing failures include older account navigation, catalog/card-view layouts, player control/drawer expectations, subtitle/recording UI expectations and profile chooser wording. A clean pre-change checkout was not run; these are reported separately rather than claiming all are independently proven pre-existing.
- Release APK built with the existing development configuration. Physical installation/navigation/frame profiling remains blocked: ADB at 192.168.2.12:5555 is unreachable. No 60 FPS or physical-device success claim is made.

## Fire TV validation still required before rollout

Use the real Movies grid and Android D-pad input. Check first/last/top/bottom cards at the actual TV viewport; rapidly traverse rows; dwell on a poster; enter Play/Details/My List; dismiss with Back; return from Details and playback and confirm exact poster focus and scroll. Scroll an expanded anchor off-screen and change category/sort. Verify only one preview, no orphan overlays, no clipping/sidebar overlap, and no extra metadata requests. Profile frame timing and memory using a release/profile build. Do not enable additional screens until these checks succeed.

## Full-suite failures

- test/account_navigation_test.dart: switch account returns to chooser and removal is settings only [E]
- test/card_view_test.dart: live horizontal rows, All and back [E]
- test/card_view_test.dart: movies horizontal rows, All and back [E]
- test/card_view_test.dart: series horizontal rows, All and back [E]
- test/edit_account_test.dart: settings edits the current account and Cancel discards changes [E]
- test/dashboard_test.dart: dashboard fits TV layout and opens Movies from navigation [E]
- test/epg_test.dart: live player opens transparent right-side guide with current programme [E]
- test/fire_tv_remote_test.dart: Select activates focused player controls and arrows move focus [E]
- test/history_regression_test.dart: leaving playback before ten-second timer refreshes Continue Watching immediately [E]
- test/history_regression_test.dart: an already open details page refreshes Resume when player progress changes [E]
- test/fire_tv_remote_test.dart: Down moves across card categories beyond the initially visible rows [E]
- test/fire_tv_remote_test.dart: category locks can be set in Settings without controls in browsing [E]
- test/live_player_initial_focus_test.dart: Live TV starts without focused controls and first remote press focuses without activating [E]
- test/live_recording_test.dart: Live TV categories expose the Live TV recording library [E]
- test/live_stream_recovery_test.dart: live player reopens an ended stream and respects a manual pause [E]
- test/live_tv_experience_test.dart: Back hides visible live controls, then exits to the previous screen [E]
- test/live_tv_test.dart: live controls hide subtitles and channel picker switches playback and EPG [E]
- test/live_tv_test.dart: live navigation is wide with compact rows and matching My list width [E]
- test/live_tv_toolbar_test.dart: equal toolbar buttons and visible Back exits Live TV [E]
- test/live_tv_toolbar_test.dart: remote Back hides controls then exits Live TV [E]
- test/m3u_account_test.dart: startup Add profile opens connection choices and Cancel returns to chooser [E]
- test/my_list_test.dart: save and remove live from My list [E]
- test/my_list_test.dart: save and remove movies from My list [E]
- test/my_list_test.dart: save and remove series from My list [E]
- test/next_episode_autoplay_test.dart: Play uses exactly the same circular styling as My List [E]
- test/next_episode_autoplay_test.dart: horizontal countdown runs for fifteen seconds and plays exactly once [E]
- test/next_episode_autoplay_test.dart: only end-of-media starts autoplay and the next episode is returned after fifteen seconds [E]
- test/player_back_control_test.dart: top back arrow exits VOD player immediately with controls visible [E]
- test/player_back_control_test.dart: top back arrow exits live player immediately with controls visible [E]
- test/player_drawer_test.dart: compact full-height drawer separates selection and focus at Size(1280.0, 720.0) [E]
- test/player_drawer_test.dart: compact full-height drawer separates selection and focus at Size(1920.0, 1080.0) [E]
- test/profiles_locks_test.dart: startup shows named avatars and add-account offers all available avatars [E]
- test/recordings_test.dart: Record writes a profile file, shows status and saves; library control is absent [E]
- test/settings_cards_focus_test.dart: Settings cards open separate panels and Back returns to cards [E]
- test/settings_test.dart: centered home opens settings and switches to fresh credentials [E]
- test/subtitle_test.dart: player uses cinematic controls and applies existing playback speeds [E]
- test/video_display_test.dart: zoom in, out and reset apply to video [E]

## Netflix-style Movies browsing update

The Movies category rows now share the floating preview controller with the full Movies grid. Normal cards retain their smaller sizes. Focus widens the preview beyond the normal cell; after 450 ms its metadata panel appears beneath the title. Cached provider details supply synopsis, genre and runtime alongside listing year/rating. One serialized metadata lane skips obsolete queued focus work, and existing catalog futures deduplicate repeated requests. Available backdrops use the shared optimized artwork repository. No video preview/player is created. Rows retain Up/Down category navigation and OK opens existing details; full-grid preview actions retain their existing behavior. Main catalog Back still returns normally. Both horizontal and vertical scrolling invalidate off-screen previews. Series and Lite are unchanged.

Reference inspected: https://www.netflix.com/tudum/articles/netflix-new-homepage-layout-user-guide . Netflix describes focus-based discovery with synopsis, runtime and ratings. This is a Streamora implementation of that interaction pattern, not a copy of Netflix artwork or branding.
