# Trailers & Coming Soon

## User experience

The dashboard has a **Trailers** entry beside Movies and Series. It opens a dark, cinematic discovery page with a focus-updated featured movie, optimized backdrop, release information, synopsis, trailer preview and actions. Lazy horizontal rows show Upcoming Hollywood Releases, Upcoming Bollywood Releases, Popular Trailers and Now in Theaters. Upcoming Releases uses future original-release and regional theatrical date filters, then locally excludes past dates, today and missing dates, and sorts nearest release first; this also applies to cached responses and View All pages. View All opens paginated collections. An always-present Reminders collection lists saved titles.

Use Left/Right within a row, Up/Down between rows and featured controls, and OK to open movie details. Right from the last card reaches View All; Left/Down from View All returns to the row. Returning from details or trailer playback restores focus. Cards expand 1.06 without reflow, with a blue border and subtle shadow. Hero metadata updates after a 170 ms debounce; merely focusing a card never plays video.

Details show synopsis, release date, genres, runtime, regional certification and TMDB rating when available. Missing dates/artwork/trailers have honest fallback states. Metadata and controls render without waiting for image downloads.

## TMDB endpoints and configuration

The existing `TmdbCastService` transport and cache-file infrastructure are reused. No IPTV credentials are passed to TMDB.

- `GET /discover/movie?primary_release_date.gte=<tomorrow>&release_date.gte=<tomorrow>&with_release_type=2|3&sort_by=primary_release_date.asc&language=...&region=...&page=...`
- `GET /movie/popular?language=...&region=...&page=...`
- `GET /movie/now_playing?language=...&region=...&page=...`
- `GET /movie/{id}?append_to_response=videos,images,release_dates&language=...`
- `GET /movie/{id}/videos?language=...`

Existing `TMDB_READ_ACCESS_TOKEN` continues working. `TMDB_API_READ_TOKEN` is an accepted alias and takes precedence when configured. Optional defines:

```text
TMDB_API_BASE_URL=https://api.themoviedb.org/3
TMDB_REGION=CA
TMDB_LANGUAGE=en-CA
```

The default API base is TMDB v3. Region/language otherwise follow the app locale, with US as the country fallback only when the locale supplies none. The existing ignored development configuration already supplies a token; no credentials were added to source or this document. The TMDB attribution remains in Settings, with attribution also visible on discovery. Production licensing/commercial usage requires separate review; this implementation makes no commercial licensing claim.

## Trailer selection and playback

Videos must be YouTube entries with valid IDs and a permitted preview type. Selection order is official trailer, other trailer, official teaser, other teaser, then clip. Newer publication dates break ties. Labels distinguish official/nonofficial content and teasers/clips; a missing video never produces a broken Play button.

The existing in-app `YoutubeTrailerScreen` and official IFrame Player API are reused. There is no stream extraction, branding/ad removal or feeding watch-page URLs to the IPTV decoder. Only explicit playback creates a player. Repeated OK presses cannot stack trailer routes. Back/Esc returns and restores focus; loading/error states and remote playback controls remain available.

For this discovery feature, an embedding failure can offer **Open in YouTube**, only after compatible HTTPS handling is detected. This is an explicit action, never an automatic redirect. Existing movie/series trailer behavior defaults to in-app-only. The Android manifest includes the package-visibility query required to check HTTPS handling.

## Remind Me and profile safety

`TrailerReminders` uses the current profile's existing secure-storage infrastructure and a separate `trailer_reminders:<scope>` key. It stores TMDB IDs and movie metadata; it does not store provider stream URLs. Writes are serialized and committed before UI state changes. Add/remove survives application restarts, and identically named movies remain distinct by ID.

Remind Me changes to Reminder Set and stores per-profile release-date and library-availability preferences. Select Reminder Set to edit preferences or remove the reminder. The Reminders collection stays separate from provider My List IDs.

The dashboard checks due release reminders at startup and resume. The existing movie catalogue cache passes its fetched items to the availability checker; reminder checks never download another playlist. Matching uses provider TMDB IDs when available, otherwise normalized title and release year plus corroborating cast or runtime metadata. Conflicting TMDB IDs are rejected, and uncertain matches remain pending. Category and title restrictions apply.

Notification events and read state persist with the reminders. Each release-date event and library-availability event is emitted once, including across restarts. A dashboard bell shows unread counts and opens notification cards with a View Movie Details action. These are in-app notifications; no background service or OS notification scheduling is required. Trailers shares the dashboard's collapsible navigation rail with Movies and Series.

Discovery is unavailable in Kids profiles. For **Available in My IPTV**, title plus release year must match conservatively against the existing provider catalog. Hidden, locked and Kids-disallowed provider items are filtered. Unknown-year/ambiguous name variants may not match; the app does not guess availability. Quality/language versions that match are offered individually with their original provider IDs. Selecting one opens the existing provider details/playback path. Discovery TMDB IDs are never resolved as IPTV IDs. Provider authentication and movie playback are unchanged.

## Caching, Lite Mode and performance

- One repository serves Premium and Lite.
- Metadata responses have a six-hour memory/disk cache, keyed by endpoint, language, region and API base; stale cached data can be used on network failure.
- Identical in-flight metadata calls are deduplicated through the shared request queue. Selected details have foreground priority.
- Popular rows validate only the requested page's video metadata in batches of four; they do not fetch full details/artwork for every movie. An unavailable batch stops further scanning rather than hammering a rate-limited API.
- Artwork uses `SharedArtworkImage` and the existing disk/decoded caches, visibility checks and decode constraints. The models request sized CDN assets (w342 posters, w300 cards and w780 hero paths); the shared repository may adjust those to its configured artwork-kind variants. Originals are not requested.
- Lite renders text-first lists and skips artwork widgets, including large backdrops and YouTube preview thumbnails. Discovery text metadata and trailer playback still work.
- Pagination is capped at TMDB's supported 500 pages and duplicate IDs are merged. No multiple trailer-player preload is performed.

These are structural optimizations, not measured Fire TV speed claims.

## Files

Created:

- `lib/domain/trailer_movie.dart`
- `lib/data/trailers_repository.dart`
- `lib/application/trailer_reminders.dart`
- `lib/application/trailer_catalog_match.dart`
- `lib/presentation/trailers_screen.dart`
- `test/trailers_repository_test.dart`
- `test/trailers_screen_test.dart`
- `docs/trailer_discovery.md`

Modified:

- `lib/data/tmdb_cast_service.dart` — configurable shared transport and safe HTTP status errors.
- `lib/presentation/dashboard.dart` — Trailers navigation, hidden for Kids profiles.
- `lib/presentation/media_horizontal_rail.dart` — optional right-boundary focus callback; existing rails retain their behavior.
- `lib/presentation/trailer_screen.dart` — opt-in error-only external fallback and duplicate-player guard.
- `android/app/src/main/AndroidManifest.xml` — HTTPS handler visibility query.

## Validation and device limitations

Real configured API smoke checks returned 20 entries from each discovery endpoint and valid detail/video metadata. No IPTV stream was opened for this check. Automated tests cover parsing, video priority, missing videos, paging, request deduplication/refresh, cache fallback, auth/rate limits/timeouts, reminders/restart/profile isolation, matching restrictions, Kids blocking, remote focus/restoration, empty states and Premium/Lite layouts at 960x540, 1280x720 and 1920x1080.

Final `flutter analyze --no-pub` completed with no issues. The final discovery/trailer feature suite passed 21 tests; an earlier focused related regression suite passed 66 tests. A full `flutter test --no-pub` run recorded 475 passing and 36 failing tests. The failures are in existing account/player/settings/older-layout expectations; the discovery-specific tests pass. The full suite is not claimed green. Related trailer, movie/series details, dashboard remote, catalog My List, artwork and VOD controls regressions are run separately.

Android checks for a current WebView package before constructing the embedded player; unavailable native components stay in a readable in-app error state. Physical Fire TV verification is still needed for embedded YouTube playback/WebView availability, D-pad behavior on the actual remote, cold-cache artwork behavior, scrolling smoothness and memory use. No support claim is made for every Fire TV model. Builds are prepared locally, not installed automatically.

Final Windows profile and Android profile builds succeeded. Android artifact: build/app/outputs/flutter-apk/app-profile.apk. Windows artifact: build/windows/x64/runner/Profile/iptv_flutter.exe. Neither was launched or installed for physical-device testing as part of this feature.

### Upcoming discovery and trailer controls
Upcoming releases use global primary release dates after today, ordered earliest first. Upcoming Releases is limited to English-language US-origin productions as the Hollywood filter; there is no separate Hindi upcoming row. Regional re-release dates do not qualify an older film as upcoming.

Catalog matching strips provider language suffixes before comparing title and release year. This supports entries such as Verity (2026) (English) and Verity (2026) (Hindi). Failed catalog lookups show a retry state rather than an absence claim.

The embedded trailer opens without an app bar and reuses the movie control component for play/pause, seeking, progress, and Back. The dock hides after five seconds during playback. It sits outside the YouTube viewport so official controls and branding remain unobscured. Physical Fire TV verification remains pending.


Trailer details now append TMDB credits and display cast names, roles, and available photos (text only in Lite Mode). Embedded YouTube playback uses only official YouTube controls, a stable expanded viewport, and a compact Back strip outside the video. Remote Back/Esc exits. This supersedes the movie-control dock described above.
