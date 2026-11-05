# Universal Search

Dashboard Search now pushes a dedicated full-screen route. The existing per-catalog search pages remain available. Result activation uses Dashboard.openItem, including current profile restrictions and existing Movie/Series Details and Live TV playback.

## Files

Created:
- lib/application/universal_search.dart: provider-scoped reusable normalized index, ranking, cooperative chunked filtering, debounce, stale-query cancellation, partial loads and restrictions.
- lib/data/recent_searches.dart: serialized, profile-scoped secure-storage history; eight unique recent queries.
- lib/presentation/universal_search_screen.dart: Premium poster rails, Live TV logos/current EPG, Lite text rows, filters, recent history, Recently Added, remote traversal, keyboard and return-state handling.
- test/universal_search_test.dart: normalization/ranking/version preservation, 50,000-title index, cancellation/cache reuse, history isolation, debounce/invalidation and Premium/Lite widgets.

Modified for this feature:
- lib/presentation/dashboard.dart: universal search entry and duplicate route guard.
- lib/presentation/activation_text_field.dart: optional explicit-submit/edit-state callbacks and keyboard dismissal access. Focus loss does not submit.
- lib/application/recent_catalog_cache.dart: revision notification for search invalidation.

No new dependencies. No new player or backend.

## Data and performance

Each supported catalog loads independently from RecentCatalogCache. A cold full-catalog cache requires one existing provider metadata request per supported type. Subsequent queries and filter changes are local. Index construction and search yield every 512 records. Catalog refresh and restriction changes invalidate the search view. Provider replacement rebuilds against the new provider and profile history scope. Artwork is constructed only for lazily built Premium cards; Lite constructs no image widgets. Live EPG is optional, loaded once per visible channel/provider and reused during this provider session.

History is saved only on explicit submission, recent-query activation or result selection. Recently Added uses provider timestamps and omits undated items rather than inventing recency. Distinct content IDs remain separate even when titles match.

## Verification

Automated targeted suites: universal_search_test, lite_mode_test, series_catalog_screen_test, movie_catalog_screen_test. Search-index tests cover 50,000 metadata records; they do not measure hardware frame rates.

Remaining manual Fire TV checks:
1. Open dashboard Search: search field highlighted; keyboard opens only on OK.
2. Type a title; traverse All/Live TV/Movies/Series and grouped rails. Press Up from a rail with additional matches to reach View All, then OK; query remains unchanged.
3. Open and return from movie/series details and Live TV; verify selected result, query and scroll position.
4. In Lite, traverse text results with Up/Down and verify no artwork traffic.
5. Submit/select queries, restart and switch profiles; verify history isolation and Clear history.
6. Back closes an active keyboard before leaving Search. Test Escape on desktop separately.
7. Check slow/offline providers: available types remain searchable while other types load or fail; Retry recovers failed metadata requests.

Limitations: first search on a cold provider depends on provider catalog response times. EPG/programme labels depend on provider capability. Network/history storage failures do not expose raw server errors. Real Fire TV responsiveness and platform-keyboard behavior require the above device checks; no TV install is performed by this change.
