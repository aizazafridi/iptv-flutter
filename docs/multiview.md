# Multi View

Implemented for the existing media_kit/libmpv player; no ExoPlayer/Media3 replacement.

## Playback and ownership

- Normal Live TV finishes recording and stops its engine before opening Multi View.
- MultiViewController owns each populated panel's independent engine and stable video surface. Empty panels own no engine. Initialization/channel changes are serialized and wait for readiness (20-second bound) before starting the next player.
- Stream URLs and HTTP headers come from the existing provider resolver and pass unchanged to MediaKitEngine. Retrying a failed panel resolves fresh provider playback metadata. There are no fabricated quality URLs or mock production streams.
- Audio is muted before opening any additional engine. Switching audio first mutes every session, then unmutes the selected session. An engine without mute support is rejected.
- Swapping moves panel session identities/surfaces without reopening streams; audio follows its session. Focusing panels changes only the border color, not video size.
- Reducing layouts disposes hidden engines, retaining their assignments. Expanding restores assigned streams sequentially. Full-screen expansion retains its own player and disposes the others; Back restores the grid.
- Backgrounding/audio interruptions release players. Resuming restarts only visible assigned sessions. The Android bridge requests one application-level audio-focus session.
- Exit disposes every Multi View engine before returning the selected (or audio-focused fallback) channel/source to the original Live TV player. That original player remains owned by PlayerScreen and is restarted only after Multi View's route has completed.

## Interface and remote

Dark navy header, 4/2/3 Screens selector, rounded panels with channel labels, cached-only logos, audio and expand actions, blue focus outlines, and bottom Channel List / Swap Screens / Audio Focus / Layouts / Exit toolbar.

Layouts: 2 equal columns; 3 uses 65% primary and 35% stacked secondary panels; 4 is a 2x2 grid. Default is 2. The last layout and supported settings persist through PlaybackPreferences in a separate per-profile namespace so ordinary playback settings cannot overwrite them.

Settings: default layout, names, cached logos, preferred audio screen, auto-hide toolbar, Fit/Fill. Screen 1 always begins with audio; preferred audio can select another assigned panel. PiP is hidden because this app has no supported system-PiP implementation.

OK on an empty panel opens the existing channel browser in a 35% left drawer. It retains provider categories, search, EPG, My List groups and PIN checks. Selection closes the drawer and replaces only its target panel. OK on a populated panel opens Change Channel / Listen / Full Screen / Swap / Remove; failed panels also offer Retry. Retry is explicit and does not loop indefinitely.

Grid arrows follow 2/3/4-panel geometry. At edges, Up reaches layout controls and Down reaches the toolbar. Toolbar Left/Right changes actions and Up returns to the selected panel. Back closes dialogs first, then cancels swap, returns from full screen, or exits Multi View. Escape works on desktop.

## Resource and provider safeguards

Xtream max_connections is exposed through the optional StreamLimitProvider interface and forwarded by LockedProvider. Known limits prevent creating an extra stream. Null/zero means unknown/unlimited, not a promise of four connections. Other devices/apps may consume the same subscription limit; the account's advertised maximum is not a live reservation system.

Android MediaCodecList reports AVC/HEVC decoder upper bounds in Settings. Android documents that actual usable instances can be lower, depending on resources and streams: https://developer.android.com/reference/android/media/MediaCodecInfo.CodecCapabilities#getMaxSupportedInstances()

Decoder counts are diagnostic hints, not a hard codec-agnostic limit. Startup/runtime failures affect only their panel, offer Retry / Change Channel / fewer screens, and preserve working sessions. Sustained buffering warns about bandwidth. This implementation does not auto-select unadvertised lower-quality URLs.

Multi View uses bounded 8 MB forward / 2 MB back buffers with six seconds of caching per engine; normal Live TV keeps its existing buffers. No real-time blur. Logos are disk-only in Premium and absent in Lite. Lite reduces UI/artwork work, not video decoding requirements. Video progress does not rebuild the grid after initial readiness.

## Verification and device follow-up

Automated engine tests cover lazy startup, four independent assignments, one-audio ownership, swapping without restart, layout reduction/restoration, fullscreen suspension, lifecycle cleanup, provider limits, failed resolution preserving an old stream, per-panel decoder failures, fresh-URL retry and preserved headers.

Widget tests cover controlled single-player handoff/return, left drawer selection, exclusive audio, layout/fullscreen/cleanup, four-panel remote geometry and Back/focus restoration at 960x540 and 1280x720. These use injected test engines; they do not prove device decoding capacity.

A release APK was built, including the Android bridge. No physical Fire TV installation or live-stream benchmarks were performed for this change, per the current build-only instruction. No hardware compatibility or throughput/frame-drop improvement is claimed.

Remaining Fire TV checks: start two actual streams, then add three/four only within subscription limits; exercise mixed AVC/HEVC and HD/4K streams; verify mute/system interruption/Back/keyboard; check Home/resume, profile exit and decoder release; monitor process memory, dropped frames, buffering and network usage. Test on both older and newer Fire TV devices.

## Files in this implementation

Created:
- lib/application/multiview_controller.dart
- lib/playback/multiview_platform.dart
- test/multiview_controller_test.dart
- docs/multiview.md
- docs/multiview-test-results.md

Updated:
- lib/presentation/live_multiview_screen.dart (complete UI and session integration)
- lib/presentation/player_screen.dart (handoff and continuation)
- lib/presentation/live_tv_controls.dart (Multi View entry label)
- lib/presentation/live_channel_browser.dart (embedded mode reusing existing behavior)
- lib/playback/media_kit_engine.dart (optional Multi View buffer budget)
- lib/domain/iptv_provider.dart (optional advertised stream-limit capability)
- lib/data/xtream/xtream_provider.dart (read max_connections)
- lib/data/locked_provider.dart (forward optional limit)
- android/app/src/main/kotlin/com/iptv/iptv_flutter/MainActivity.kt (audio focus and codec diagnostics)
- test/live_multiview_test.dart (handoff, audio, layouts, fullscreen, remote and cleanup)
- test/live_tv_toolbar_test.dart (updated action name)
- test/weather_on_now_test.dart (isolate persistent fixtures across test clocks to allow the full suite to complete)
