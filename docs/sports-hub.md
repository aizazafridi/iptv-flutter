# Sports Hub

## Integration and files

- `lib/domain/sports.dart`: normalized Sport, SportsLeague, SportsTeam, SportsEvent, statuses, provider interface.
- `lib/data/the_sports_db_provider.dart`: v1 parsing, configuration, shared production throttling, bounded retry, cancellation of obsolete queued schedules, optional backend gateway boundary.
- `lib/data/sports_api_cache.dart`: memory + existing FlutterSecureStorage persistence; stale-while-revalidate, request deduplication, failed refresh cooldown. Public sports metadata only, keyed by endpoint identity hash, no IPTV credentials.
- `lib/application/sports_repository.dart`: local calendar dates mapped to intersecting UTC schedule dates, deduplication, followed teams/leagues aggregation.
- `lib/application/sports_favorites.dart`: serialized, profile-scoped follow/unfollow persistence, commits only after successful write.
- `lib/application/sports_channel_matcher.dart`: conservative EPG evidence classification, original ContentItem IDs retained.
- `lib/presentation/sports_hub_screen.dart`: hub, lightweight event cards, match details, team search, channel tiles. Uses existing routes, ActivationTextField, SharedArtworkImage and browsing modes.
- `lib/presentation/dashboard.dart`: Sports navigation; uses the dashboard's existing openItem callback for Live TV playback and access checks.
- `test/sports_data_test.dart`, `test/sports_hub_test.dart`: adapter, storage, cache, matcher, UI and remote focus tests.

Branding stays Streamora to match the actual application (the request's StreamFlix name is not a product rename).

## Screens and behavior

Sports is under TV Guide in the sidebar. Sport filters use returned provider names (Soccer is displayed as Football); no fixtures or teams are shipped as sample production content. Only provider-listed sports appear. Today shows available events on the device's local calendar day, querying the intersecting UTC dates and filtering absolute instants locally. Upcoming defaults to the next local day; selecting a league uses its next-events endpoint. Following teams/leagues enables their aggregated schedules. Results defaults to the previous local day or uses selected/followed leagues and teams. Scores remain strings, preserving sport-specific provider values. Missing values stay unknown.

Match details offers team/league follow controls and explicit Find Channels. No reminder control is shown, as this implementation adds no reminder service. Team search uses the provider endpoint and rejects unrelated results rather than substituting Arsenal for other searches. Following dialog supports explicit unfollow actions. Profiles share public fixture data but never favorites or IPTV channel references.

Your Sports Channels works independently of the sports API: prioritize channels in sports-named custom groups, then saved sports channels, then remaining recognizable sports channels. Hidden/configured-locked channels are excluded. Playback resolves the current provider ID again before delegating to existing dashboard openItem, which performs its normal access checks and uses the existing PlayerScreen. No extra engine, stream URLs, authentication, or connection-limit changes.

## Endpoints

Official reference: https://www.thesportsdb.com/documentation

- all_sports.php / sports
- all_leagues.php / leagues
- eventsday.php?d=YYYY-MM-DD[&s=provider sport name] / events
- eventsnextleague.php?id=league / events
- eventsnext.php?id=team / events
- eventspastleague.php?id=league / events
- eventslast.php?id=team / results
- searchteams.php?t=query / teams
- lookupleague.php?id=league / leagues
- lookupteam.php?id=team / teams
- lookupevent.php?id=event / events

Observed public-key responses during implementation: all_sports returned 2 sports, all_leagues 10 leagues, daily schedules 3 events, upcoming league schedules 1 event. These are limited available results, never an exhaustive global schedule. Official documentation also restricts free team search to Arsenal, with next/past team events limited to home games. Coverage can change and differ by endpoint. Missing results do not prove a match or team does not exist.

## Caching and network

Sports/leagues/team metadata: 24 hours; daily/event details: 20 minutes; upcoming: 2 hours; results: 45 minutes. Endpoint identity segregates different backend bases. Stale saved schedules render immediately and refresh in the background; successful refreshes update the screen in place. Failed stale refreshes pause retries for a minute. Production adapters share a serial request gate with at least 2.1 seconds between starts, fewer than 30 starts/minute. HTTP 429 honors numeric Retry-After with at least 60 seconds cooldown and does not loop retry. Transient network/5xx errors get at most one retry after a 2-second delay (the serial throttle remains active); timeout is 15 seconds. Closing the hub skips queued work, and changing filters invalidates obsolete queued schedule jobs. Already-sent HTTP requests cannot be individually cancelled by package:http; stale UI generations are ignored.

Logos use the shared image cache and TheSportsDB's documented /tiny variant. Lite builds no image widgets and has no scale animation. Metadata is independent of logo downloads. Cards have fixed icon dimensions, small focus expansion and blue outlines. Event focus nodes survive refresh and are restored after returning from details; existing navigator behavior restores focus after playback.

## Channel evidence and limitations

EPG discovery is explicit, bounded to 24 candidate playlist sports/group channels, two workers. It calls the existing EpgProvider API; no second EPG parser is introduced. Results appear progressively while the scan runs; it uses existing provider timeout behavior so timed-out wrapper futures cannot leave extra parallel EPG requests running. A verified match requires both full team names and competition in EPG evidence, plus the scheduled start within its programme window (up to 15-minute pre-show tolerance). Highlights/replays/repeats/classics are rejected. Both teams/time without competition is only Possible. Sports channel naming without event evidence is Related only. Region prefixes and meaningful names remain distinct; quality suffixes and separators are normalized for discovery only.

The first version intentionally does not use the limited eventstv endpoint: its one-row free coverage is not sufficient for general region-specific broadcast guarantees. No broadcaster associations or rights are invented. The bounded EPG scan may miss valid broadcasts; renamed non-sports channels can only be verified when their EPG is supplied to the matcher. No verified result means no confirmation was found, not that no broadcaster exists.

## Configuration and premium/backend readiness

Existing --dart-define / --dart-define-from-file configuration is used. Development needs no extra credentials:

```
SPORTS_API_MODE=free_v1
SPORTS_API_BASE_URL=https://www.thesportsdb.com/api/v1/json/123/
SPORTS_API_KEY=123
```

Only public key 123 is accepted for direct free requests. Never embed paid credentials. No changes were made to config.dev.json or existing IPTV credentials.

For a future gateway:

```
SPORTS_API_MODE=backend
SPORTS_API_BASE_URL=https://your-authorized-service.example/sports/v1/
SPORTS_LIVE_SCORES=true
SPORTS_FULL_COVERAGE=true
```

Backend flags default to false; do not enable until the service actually supplies the capability. No backend is deployed by this task. The compatibility gateway must expose the listed read-only endpoint/response schemas, translate upstream paid v2 authentication server-side (X-API-KEY), enforce authorization/rate limits/cache/allowlists, and omit upstream credentials. live_scores.php is a gateway-only contract, not a claimed TheSportsDB v1 endpoint; it must return an events array with fresh provider status evidence. Live responses bypass schedule caching; explicit live view refreshes at most once/minute while foreground/current, clearing old scores before fetching. There is no free simulated live feed. A fully normalized backend can instead implement SportsDataProvider without changing the hub UI. Authentication for a private gateway must be supplied by that future adapter using the backend's actual session mechanism, not compiled provider secrets.

Before publication, arrange appropriate commercial usage, verify current data and artwork rights and required attribution/cache/redistribution rules with the provider. The public free key is a development/testing integration, not a production licensing claim. Sports data access provides no streaming rights; the hub opens only the user's existing IPTV channels.

## Device validation remaining

No physical Fire TV test or installation was performed for this feature. Validate sidebar entry, horizontal filters and league dialog, long match names, scrolling both directions, team-search keyboard/Back, focus after API refresh, detail/channel/playback Back restoration, hidden/PIN-locked channels, profile switching, cold/warm cache, disconnect/reconnect and actual EPG evidence on a TV. Premium live/backend behavior requires a real contracted service and cannot be verified against key 123.

## Verification

Full suite during implementation: **372 passed, 37 failed**. The sports data and UI tests passed. Existing dashboard remote tests passed. The broader failures were in account/card-view, profile and player/subtitle expectations; a clean baseline was not run, so they are not independently asserted to all predate this task. Failure list:

```text
00:01 +10 -1: C:/iptv-flutter/test/account_navigation_test.dart: switch account returns to chooser and removal is settings only [E]
00:02 +11 -2: C:/iptv-flutter/test/card_view_test.dart: live horizontal rows, All and back [E]
00:02 +14 -3: C:/iptv-flutter/test/card_view_test.dart: movies horizontal rows, All and back [E]
00:02 +16 -4: C:/iptv-flutter/test/card_view_test.dart: series horizontal rows, All and back [E]
00:09 +56 -5: C:/iptv-flutter/test/edit_account_test.dart: settings edits the current account and Cancel discards changes [E]
00:10 +57 -6: C:/iptv-flutter/test/dashboard_test.dart: dashboard fits TV layout and opens Movies from navigation [E]
00:12 +64 -7: C:/iptv-flutter/test/epg_test.dart: live player opens transparent right-side guide with current programme [E]
00:13 +71 -8: C:/iptv-flutter/test/fire_tv_remote_test.dart: Select activates focused player controls and arrows move focus [E]
00:17 +91 -9: C:/iptv-flutter/test/history_regression_test.dart: leaving playback before ten-second timer refreshes Continue Watching immediately [E]
00:17 +91 -10: C:/iptv-flutter/test/history_regression_test.dart: an already open details page refreshes Resume when player progress changes [E]
00:22 +108 -11: C:/iptv-flutter/test/fire_tv_remote_test.dart: Down moves across card categories beyond the initially visible rows [E]
00:22 +111 -12: C:/iptv-flutter/test/fire_tv_remote_test.dart: category locks can be set in Settings without controls in browsing [E]
00:25 +124 -13: C:/iptv-flutter/test/live_player_initial_focus_test.dart: Live TV starts without focused controls and first remote press focuses without activating [E]
00:26 +127 -14: C:/iptv-flutter/test/live_recording_test.dart: Live TV categories expose the Live TV recording library [E]
00:28 +132 -15: C:/iptv-flutter/test/live_stream_recovery_test.dart: live player reopens an ended stream and respects a manual pause [E]
00:29 +137 -16: C:/iptv-flutter/test/live_tv_experience_test.dart: Back hides visible live controls, then exits to the previous screen [E]
00:30 +139 -17: C:/iptv-flutter/test/live_tv_test.dart: live controls hide subtitles and channel picker switches playback and EPG [E]
00:30 +141 -18: C:/iptv-flutter/test/live_tv_test.dart: live navigation is wide with compact rows and matching My list width [E]
00:31 +143 -19: C:/iptv-flutter/test/live_tv_toolbar_test.dart: equal toolbar buttons and visible Back exits Live TV [E]
00:31 +146 -20: C:/iptv-flutter/test/live_tv_toolbar_test.dart: remote Back hides controls then exits Live TV [E]
00:33 +153 -21: C:/iptv-flutter/test/m3u_account_test.dart: startup Add profile opens connection choices and Cancel returns to chooser [E]
00:35 +166 -22: C:/iptv-flutter/test/my_list_test.dart: save and remove live from My list [E]
00:35 +166 -23: C:/iptv-flutter/test/next_episode_autoplay_test.dart: Play uses exactly the same circular styling as My List [E]
00:35 +166 -24: C:/iptv-flutter/test/my_list_test.dart: save and remove movies from My list [E]
00:35 +167 -25: C:/iptv-flutter/test/next_episode_autoplay_test.dart: horizontal countdown runs for fifteen seconds and plays exactly once [E]
00:36 +168 -26: C:/iptv-flutter/test/my_list_test.dart: save and remove series from My list [E]
00:36 +169 -27: C:/iptv-flutter/test/next_episode_autoplay_test.dart: only end-of-media starts autoplay and the next episode is returned after fifteen seconds [E]
00:40 +196 -28: C:/iptv-flutter/test/player_back_control_test.dart: top back arrow exits VOD player immediately with controls visible [E]
00:40 +196 -29: C:/iptv-flutter/test/player_back_control_test.dart: top back arrow exits live player immediately with controls visible [E]
00:41 +196 -30: C:/iptv-flutter/test/player_drawer_test.dart: compact full-height drawer separates selection and focus at Size(1280.0, 720.0) [E]
00:41 +203 -31: C:/iptv-flutter/test/player_drawer_test.dart: compact full-height drawer separates selection and focus at Size(1920.0, 1080.0) [E]
00:42 +208 -32: C:/iptv-flutter/test/profiles_locks_test.dart: startup shows named avatars and add-account offers all available avatars [E]
00:48 +236 -33: C:/iptv-flutter/test/recordings_test.dart: Record writes a profile file, shows status and saves; library control is absent [E]
00:51 +243 -34: C:/iptv-flutter/test/settings_cards_focus_test.dart: Settings cards open separate panels and Back returns to cards [E]
00:52 +245 -35: C:/iptv-flutter/test/settings_test.dart: centered home opens settings and switches to fresh credentials [E]
00:59 +310 -36: C:/iptv-flutter/test/subtitle_test.dart: player uses cinematic controls and applies existing playback speeds [E]
01:04 +344 -37: C:/iptv-flutter/test/video_display_test.dart: zoom in, out and reset apply to video [E]
```

Final targeted run: **41 passed** (30 sports data tests, 9 sports UI tests, 2 existing dashboard remote tests). This includes D-pad filter/section traversal and cancellation of obsolete queued requests. Full-suite totals above precede the final two added focused tests. Analyzer: **No issues found**. No install, app launch or physical-device performance claims.

## Compact hub layout

The hub now uses a 44-logical-pixel header, 32-pixel filter controls, 12-pixel filter/action text and compact 146/158-pixel match rows (Lite/Premium). Two columns are used from 640 logical pixels of available content width; narrower windows stack cards. Your Sports Channels is restored below the grid as a horizontal row of compact TV-icon tiles using the existing provider channels and playback callback. The current 11 Sports Hub widget tests cover compact layout, focus, Cricket availability and channel playback during fixture API failure.
