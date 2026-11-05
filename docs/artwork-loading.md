# Artwork diagnosis and local implementation

## Status and measured results

Changes are local only. No Fire TV installation or configuration change was performed. The device did not respond at its previous address; the user subsequently requested that Fire TV remain unchanged. No before/after physical-device timings, upstream provider bandwidth figures, full process/GPU memory measurements, or actual display-frame-drop measurements have been collected. No speed improvement is claimed.

Verification: 107 targeted Flutter tests passed across repository/queue, artwork fallback, metadata, Movies/Series catalog/details, Search, Lite mode and VOD controls. Flutter analysis reported no issues. The metrics summarizer passed synthetic-data checks. These checks do not substitute for runtime device benchmarks.

Verified local deterministic tests, not performance benchmarks:

| Check | Observed result |
| --- | --- |
| Foreground requests held open | 4 started; later foreground work waited |
| Background requests held open | 1 started; later background work waited |
| Same-key concurrent cache reads | 1 upstream fetch for 2 consumers |
| Warm read of 1,024-byte test asset | 0 additional fetches |
| New repository using persisted cache | 0 additional fetches |
| Different signed/profile query identities | Separate cached files/fetches |
| Pending HTTP response body | Slot remained occupied until body finished |
| Request deadline | Abort trigger reached transport; no abandoned request continued behind fallback |
| Lite image adapter | No CachedNetworkImage/download widget constructed |
| Off-screen cast section | No photo download widget until scrolled into viewport |

These counts verify policy and cache behavior with controlled fixtures. They do not establish faster real-world loading.

## Diagnosis from the existing code

- CatalogPosterArtwork previously started TMDB fallback after 1.5 seconds, or 300 milliseconds for a host marked slow, while retaining the provider CachedNetworkImage in a Stack. Two different image URLs could download concurrently. This was inferred from code; actual provider traffic was not benchmarked.
- EpisodeArtwork similarly switched after 1.5 seconds without cancelling the original request.
- ContinueWatchingArtwork could construct/download a portrait while TMDB backdrop metadata was pending, and construct it again as the backdrop loading placeholder. Distinct poster/backdrop URLs are not deduplicated by a normal URL cache.
- Bulk row/cast prefetch used decode/disk-resize sizes that differed from displayed widgets. The existing cache manager already coalesces identical original URL downloads, but different ResizeImage keys can still cause extra decoded variants and local resize work.
- The legacy Artwork helper used Image.network, bypassing the persistent CachedNetworkImage disk store.
- Backdrops requested 1,920-pixel decode widths; small cast portraits requested 252 pixels. Several sizes were fixed instead of related to actual layout/DPR.
- The featured Movies/Series hero awaited a combined logo/backdrop Future before publishing either enrichment result. It now publishes whichever arrives independently.
- Movie/Series details already separated provider metadata from image downloads. That separation remains; metadata, primary actions, and synopsis do not wait for image decoding.
- The newer Episodes drawer had lost the supplied detailed series-poster fallback. It now receives that URI for artwork rendering only; the player engine and playback state are unchanged.

## Shared repository and queue

`lib/data/artwork_repository.dart` uses the existing flutter_cache_manager/CachedNetworkImage infrastructure and the same `libCachedImageData` disk store. There is one production repository, not a competing second image cache. CachedNetworkImage still manages decoded images through Flutter ImageCache. Transport uses the already-installed http package and a pooled client.

Full source URL identity, including signed/auth/account query components, is retained. Query parameters and tokens are never stripped to increase cache hits. Public CDN assets can share their public identity. Logs use a truncated SHA-256 identifier and never emit URLs, title names, filenames, or credentials.

Requests use four foreground slots (P0 visible, P1 selected/featured backdrop) and one background slot (P2 near-visible, P3 visible cast). Slots are held through the response body, not just headers. The cache manager coalesces identical in-flight file downloads; queue jobs support same-key joins. Transport streams have separate queue identities because a single-subscription response stream must not be handed to unrelated consumers. The cache manager's outer admission allowance is 32 queued operations so it does not hide priority changes behind its own FIFO; actual HTTP concurrency is still capped at 4+1.

The widget registers/unregisters demand and re-evaluates viewport intersections while scrolling. Queued work with no remaining demand is discarded. Mounted near-visible work is reprioritized when visible. Already-started downloads are allowed to finish; scrolling cannot reliably undo bytes already transferred. A 30-second safety deadline aborts an HTTP operation rather than merely timing out a Future and leaving the original download running. This is a resource bound, not a claimed speed optimization.

The obsolete independent ArtworkPrefetch queue and bulk prefetch calls were removed. P2 warming is now performed by the same visibility-gated image adapter using exactly the displayed URL/cache/decode identity. P4 off-screen images are not preloaded. Cast photos are stricter: visible only.

## Image sizes and rendering

SharedArtworkImage computes decode width from available logical width multiplied by device pixel ratio, rounds into small reusable buckets, and applies per-role caps: posters 200, cast 96, episode thumbnails 320, backdrops 960, title/channel logos 500 physical pixels. Only width is constrained so source aspect ratio is preserved. Unusually large or nonstandard source aspect ratios still need observation; exact decoded height depends on the source image.

Only known public TMDB paths are rewritten: poster w185, profile w185, still w300, backdrop w1280, logo w500. These are server-side variants; w1280 is a supported larger source for the 960-pixel decode cap, and w185 is a supported profile source for a 96-pixel decode. Existing arbitrary provider URLs and signed URLs are preserved. Smaller decode sizes reduce decoded-memory demand; they do not themselves reduce provider download bytes. Provider CDN resizing parameters have not been guessed.

TMDB documents configurable image sizes and URL construction:
- https://developer.themoviedb.org/docs/image-basics
- https://developer.themoviedb.org/reference/configuration-details

Placeholders have parent-defined dimensions and no nested image downloader. Poster/episode failures resolve alternatives sequentially. A slow original request can therefore delay fallback compared with the old timed race. This is an intentional tradeoff to avoid spending bandwidth on competing images; telemetry should determine any future endpoint-specific policy.

## Instrumentation and interpretation

Enable with `--dart-define=ARTWORK_METRICS=true`; default is off. The flag does not alter authentication. Events are available in the developer timeline and as `ARTWORK_METRIC` JSON log lines. A bounded 2,000-event ring is retained in memory.

Captured events include catalog/details open, metadata ready, usable frame, metadata-response/cache source, image URL availability, memory lookup, disk/online file readiness, queue wait, HTTP response-body bytes and duration, decoded-frame readiness, first visible display frame, cached-image memory, and aggregated Flutter frame timings.

`file_to_decoded_ms` includes file read, decoder work and scheduling. It is not isolated codec CPU time. Inspect Flutter engine image-decode events in a profile trace to separate codec work. First display is a Flutter post-frame observation, not a hardware presentation timestamp. ImageCache byte counts exclude uncached live images, GPU textures and other process memory. Flutter build/raster budget misses are not identical to actual dropped display frames. The default frame budget is 60 Hz and must match the benchmark device.

Summarize logs locally:

```
python tools/summarize_artwork_metrics.py cold.log warm.log
```

The summarizer emits only supported counters and derived timing distributions. It never fills missing measurements with zero or invents a speedup. No telemetry is uploaded.

## Benchmark procedure, pending authorization/device access

Do not perform these steps on Fire TV until requested. For current-system manual profiling, use Windows as the target and label results as Windows; they cannot substitute for Fire TV results.

1. Use the same profile/release configuration, provider account, catalog IDs, network, display refresh rate and navigation script before/after. Instrument both versions consistently. Record cache state.
2. Cold: use a disposable test profile/cache directory or clear artwork cache only. Do not delete credentials/watch history or clear application data. Keep metadata cache state separately recorded.
3. Warm disk: reload the same titles after closing/reopening the process without deleting artwork files. Warm decoded memory: revisit in the same process; label separately.
4. Repeat at least five times: Movies catalog first visible poster, chosen Movie Details usable frame/backdrop, scroll to cast, Series catalog/details, episode row, Search and Continue Watching. Disable playback during network-byte measurement.
5. Capture ARTWORK_METRIC logs and a profile timeline. Compare p50/p95 and response-body bytes for identical routes/assets. Record source image dimensions/content lengths as well as chosen variants.
6. Capture process/graphics memory and actual presentation/frame-drop data with device tooling. Do not relabel ImageCache bytes as total image memory or frame-budget misses as exact frame drops.
7. Repeat in Lite and confirm zero new artwork HTTP starts; also verify existing video engine identity/playback continuity.

| Required physical-device metric | Before | After |
| --- | --- | --- |
| Cold first visible poster | Not measured | Not measured |
| Warm first visible poster | Not measured | Not measured |
| Movie Details usable frame | Not measured | Not measured |
| Backdrop display | Not measured | Not measured |
| Visible cast image display | Not measured | Not measured |
| Network bytes | Not measured | Not measured |
| Peak image/process/GPU memory | Not measured | Not measured |
| Scrolling frame drops | Not measured | Not measured |

## Conditional image-proxy proposal

No proxy is implemented. Consider one only if measurements show consistently slow/oversized provider assets and no supported upstream variants. It would accept authenticated opaque artwork IDs and allowlisted output presets, not arbitrary URLs. Resolve upstream URLs server-side; allowlist hosts and redirect hops, block private/link-local destinations and DNS rebinding, bound bytes/dimensions/time, validate image MIME, resize/transcode to WebP and cache with correct account/source authorization scope. Keep credentials out of public proxy URLs and shared public caches. A proxy improves payload/edge caching, not provider latency for the first uncached source fetch.

## Files and dependencies

Created: artwork_repository.dart, shared_artwork_image.dart, artwork_repository_test.dart, this report, tools/summarize_artwork_metrics.py.

Updated artwork consumers: catalog posters, Continue Watching, episode thumbnails, generic Artwork/channel logos, Movies/Series cinematic details and cast, featured catalog hero, Dashboard and Universal Search. DetailsScreen/main and TMDB services have opt-in timing hooks. Episodes drawer/PlayerScreen pass an existing poster URI; engine, playback, provider authentication and stream resolution are unchanged.

Removed: artwork_prefetch.dart and its callers.

Promoted existing transitive packages to direct dependencies: flutter_cache_manager 3.4.5, crypto 3.0.7, http 1.6.0. Offline resolution reused installed versions; no additional package implementation was introduced.


## Cold-cache catalog recovery follow-up (2026-11-03)

Category posters now gate TMDB metadata as well as image requests on actual viewport visibility (including Offstage and Lite Mode). Missing/failed fallback lookups use bounded automatic retries and update the existing card. A provider image failure promotes the card to its TMDB fallback rather than repeatedly reopening the broken provider download alongside fallback work. Item identity is captured before asynchronous lookup so results cannot be cached under a recycled card's new title.

TMDB HTTP metadata requests use the existing shared ArtworkQueue (same four foreground / one background limits), with deduplication and cast priority, rather than unconstrained concurrent requests. No second image cache was added. Featured catalog logos/backdrops also retry and publish results independently. Broken provider hero backdrops can fall back to TMDB while the page remains open.

Validation: 63 focused tests passed across posters, TMDB metadata, image repository, catalog, and movie/series details. Regression tests cover failure-to-success without reopening and no metadata requests while offstage. No physical Fire TV measurements were taken for this follow-up; cold-cache speed improvements are not claimed as measured.
