# Supplemental development sports scores

The existing TheSportsDB adapter, fixture repository, metadata/logo sources and screens are retained. No IPTV player, Xtream/M3U authentication, EPG parsing, groups, recordings, multiview or profile code was changed by this score integration.

## Files

New: `lib/domain/live_score.dart`, `lib/data/development_live_scores.dart`, `lib/application/live_score_service.dart`, `lib/application/sports_event_matcher.dart`, `test/live_scores_test.dart`, `config.sports.example.json`, this document.

Extended: `lib/domain/sports.dart` (optional score snapshot, backward-compatible copy/display getters), `lib/presentation/sports_hub_screen.dart` (generic enrichment and score source/freshness labels), `test/sports_hub_test.dart`. The ignored `config.dev.json` has local development switches and the user-supplied CricketData key; it must never be committed or printed.

## Provider behavior and documentation

- CricketData: `https://api.cricapi.com/v1/currentMatches?apikey=...&offset=0`. Batch response, provider matchStarted/matchEnded evidence, exact innings-to-team assignment, multiple innings retained, wickets/overs only when returned. Missing competition names prevent automatic attachment to TheSportsDB fixtures; explicit supplemental live cards can still show real data. First page only; never claims exhaustive coverage. Official references: https://cricketdata.org/cricket-live-score-api/ and https://cricketdata.org/pricing/ . Verified the supplied key successfully: response had 23 matches, four explicitly live and hitsLimit=100. No key is recorded here. This is access/schema validation, not a claim that every score is current or every match covered.
- balldontlie: `GET https://api.balldontlie.io/v1/games` with Authorization header and two dynamic UTC dates (yesterday/today), per_page=100. Uses actual game status/status_state, period, clock and home/visitor fields. Free games endpoint is available but not guaranteed real-time; the dedicated `/v1/box_scores/live` endpoint is paid and is not called. No account key supplied yet, so this adapter is inactive. Reference: https://docs.balldontlie.io/ . Game responses are snapshots and fetched age is labeled.
- OpenLigaDB: `GET https://api.openligadb.de/getmatchdata/bl1` (current round/current season, no year hardcoded), optional adapter-supported bl2 list. Keyless, limited German league coverage. Selects resultTypeID=2 instead of accidentally using halftime results. matchIsFinished establishes completion; unfinished matches are NOT declared live. Timezone-less lastUpdateDateTime is NOT falsely parsed as UTC. No promised update frequency. References: https://api.openligadb.de/swagger/v1/swagger.json and https://www.openligadb.de/ . Live tab may remain empty with OpenLigaDB alone because it does not authoritatively flag active matches; supported matching scores can enrich Today/Results.
- API-Football was intentionally not implemented (optional in task). It is disabled and no API-Football endpoints or keys are used.
- Premium TheSportsDB: delegates only to the existing SportsDataProvider.supportsLive/getLiveScores capability and the already documented secure backend boundary. No undocumented upstream premium endpoint was added.

## Configuration

Use existing `--dart-define-from-file=config.dev.json` and fully restart the app after changes. Safe code defaults are TheSportsDB-only with every supplemental provider off. Release builds reject development_multi_api even when explicitly supplied.

Development example (see config.sports.example.json; never put actual secrets in this tracked example):

```json
{
  "SPORTS_LIVE_SCORE_MODE": "development_multi_api",
  "CRICKETDATA_ENABLED": true,
  "CRICKETDATA_API_KEY": "",
  "CRICKETDATA_DAILY_BUDGET": 75,
  "SPORTS_SCORE_ACTIVE_DEVICES": 1,
  "BALLDONTLIE_ENABLED": false,
  "BALLDONTLIE_API_KEY": "",
  "OPENLIGADB_ENABLED": true
}
```

The real ignored development config enables CricketData with the supplied key and OpenLigaDB. balldontlie stays disabled until configured. Obtain CricketData keys from its signup/account page linked at https://cricketdata.org/how-to-use-cricket-data-api.aspx ; obtain an NBA key by registering at https://app.balldontlie.io/ . Paste keys only into ignored config.dev.json, enable that provider, and restart with that config. No API key is required for OpenLigaDB. Private keys embedded for local development are extractable from app builds; do not distribute such builds.

To stop all development score requests:

```text
SPORTS_LIVE_SCORE_MODE=thesportsdb_only
```

To migrate production scores:

```text
SPORTS_LIVE_SCORE_MODE=thesportsdb_premium
SPORTS_API_MODE=backend
SPORTS_API_BASE_URL=https://your-authorized-service.example/sports/v1/
SPORTS_LIVE_SCORES=true
```

The production gateway/adapter still needs to be implemented/deployed against contracted, documented TheSportsDB premium capabilities, server-side credentials, authorization and supported sport coverage. Changing mode alone does not grant coverage or configure credentials. Without the configured supported backend, Live shows a clear unavailable message. Premium and TheSportsDB-only modes never call development providers and never silently fall back to them. See sports-hub.md for the existing gateway compatibility contract; it is an application backend contract, not an asserted official premium endpoint. Metadata remains primary TheSportsDB content.

## Matching and source isolation

No fuzzy team-name matching. Exact normalized names or a small explicit alias set (including IND/PAK/AUS/ENG/NZ/SA and LA Lakers/Clippers) must agree, as must sport, a compatible competition, UTC calendar date and start time within 30 minutes. German display diacritics/common Bayern names are normalized. Missing times or competition evidence cause no merge. Same-team domestic/women/junior names retain their qualifiers. Competing fixtures or candidates remain ambiguous. Reversed team order remaps home/away score values.

Duplicate source event IDs collapse; cross-provider candidates that remain ambiguous are deliberately not merged. Supplemental Live cards have stable `score:provider:id` IDs, explicit source labels, no borrowed logos or foreign team/league IDs, and skip primary detail lookups. Duplicate exact supplemental event signatures are suppressed. Provider-specific event IDs stay separate in snapshots. Primary event IDs, logos, favorites and channel matching remain intact. Known primary final scores are retained unless a genuinely newer provider update timestamp proves the supplemental result is newer.

A score feed is never evidence of broadcast rights or channel availability. Existing verified/possible/related IPTV matching runs independently using its original EPG rules and original channel IDs.

## Refresh, cache, budgets and freshness

One in-flight batch per provider and service; no per-card requests. Provider memory snapshots are reused across tab changes and match details. UTC-day request counts persist via existing FlutterSecureStorage, keyed by provider and hashed credential identity (no stored raw key in cache keys). Snapshots are intentionally in memory; restarting requires a new allowed batch. Existing persistent fixture caches are unchanged.

Cricket uses a conservative 75-request/device budget by default, capped at 100 in configuration-created development adapters. Full-day pacing is at least 86400 * activeDevices / budget seconds, around 19.2 minutes with one device/75 requests, even though its base requested interval is five minutes. The interval increases with server hitsToday/hitsLimit and remaining UTC-day budget. Multiple devices sharing a key must set SPORTS_SCORE_ACTIVE_DEVICES accurately; there is no cross-device quota coordinator. Exhausted quota waits until the next UTC day. Other apps using the same key can still consume quota independently.

NBA batches are cached for at least two minutes (well below its documented five requests/minute free limit); OpenLigaDB batches for five minutes. Foreground hub/detail checks run at most once/minute and cached batches suppress premature HTTP requests; no polling while the app is backgrounded, another route is foreground, or the hub is disposed. Upcoming/My Teams are not enriched or polled; Today/Results retain primary fixtures and add matching snapshots. Hidden fixtures are not individually requested.

Errors use bounded exponential backoff, numeric Retry-After for 429, day-long pause for 401/403 and persisted quota limits. No automatic immediate retry loop. 15-second timeout. Errors expose only sanitized messages; request URLs, Authorization headers and keys are never logged. One failed provider cannot fail another provider or remove primary fixtures. Existing scores remain with fetched age and stale labels. Freshness is capped at five minutes (and at the provider refresh interval); old provider update timestamps also invalidate freshness. Stale previously-live snapshots remain clearly marked as last-known scores rather than current live data. Fetch time is never presented as a provider's actual update timestamp.

Debug-only diagnostics show mode, configured/active provider states, request counts, last successful fetch, safe errors, matches, unmatched and ambiguous counts. They are absent from release builds. Existing stable card keys/focus nodes are retained through updates; tests verify score refresh and detail Back keep focus.

## Verification

Recorded after final checks below. Physical Fire TV performance/navigation, real NBA access, real CricketData team/series coverage, all supported OpenLigaDB leagues, offline recovery across prolonged sessions and a real premium gateway still require device/service testing. No Fire TV installation or launch was performed.

Final verification: Flutter analysis reports **No issues found**. Targeted score/sports suites: **74 passed**. Full Flutter suite: **411 passed, 37 failed**, with no failures in the new live-score or Sports Hub tests. The 37 failures occur elsewhere in the existing application tests; no clean baseline checkout was run. Logs are in the local temporary folder, not committed. CricketData access was validated once with the supplied key (23 available matches, four explicitly live, 100/day plan); no NBA credentials are available, and no physical Fire TV testing was performed.
