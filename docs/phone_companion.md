# Phone companion

## Use

1. On the TV or Windows dashboard, select **Phone companion** in the left menu.
2. Select **Enable phone access**. This feature is off until explicitly enabled.
3. Connect the phone to the same home network. Scan the QR code, or enter one of the displayed addresses in the phone browser.
4. Enter the six-digit pairing code shown on the TV. Codes expire after five minutes and authorize one phone. Select **New pairing code** to pair another phone.
5. Browse/search Live TV, Movies, or Series; edit My List; create/rename/delete channel groups or assign channels to them.
6. **Open on TV** opens movie/series details. **Play / Resume on TV** uses the existing history and episode flow. **Play on TV** starts a channel. Selecting another title from the paired phone closes the previous title/player before opening the new one; it does not keep two provider streams open.

Closing the pairing dialog keeps paired phones connected. **Disconnect all phones** closes the local listener and revokes sessions. Signing out, switching profiles, or closing Streamora also ends access. Sessions expire after twelve hours. Up to four phones can pair at once. Nothing is stored in a cloud service, and browser tokens live in session storage rather than URLs.

If the phone cannot connect, check that both devices are on the same LAN, guest-network/client isolation is disabled, and Windows permits Streamora on the private network. The displayed address uses a dynamically allocated port and may change after re-enabling access. Do not configure port forwarding. HTTP is intended for a trusted home network; it is not encrypted transport.

## Ordering

Browse and My List currently follow the provider catalog order (not alphabetical or newest-first). Search ranks exact title matches, starts-with matches, contains matches, then matches containing all query words; provider order is retained within each rank.

## Scope and restrictions

The catalog uses the existing per-provider catalog cache, search indexes, My List and channel-group stores. Catalog/search requests do not open streams, fetch title details or download artwork. The phone displays lightweight text cards, including in Lite Mode. No provider credentials, stream URLs or credential-bearing artwork URLs are returned to the browser.

Hidden, PIN-configured and Kids-disallowed items are excluded even when temporarily unlocked on TV. Every favorite/membership/play action resolves its ID against the current allowed catalog. Remote navigation does not accept arbitrary playback URLs. The existing TV playback path still enforces restrictions.

Pairing is opt-in, local IPv4 only, rate-limited, short-lived and single use. API requests require a random bearer token; host/origin checks reject cross-site requests and DNS rebinding. Requests have body, concurrency and upload bounds; mutations are serialized. There is no CORS access, external web asset/CDN dependency, automatic playback on pairing, mobile video playback, or internet remote access.

## Validation

- Real loopback HTTP tests: authorization, code replay/expiry, session expiry, foreign origin/host rejection, request size/rate bounds, disconnect/profile invalidation, four-phone limit and stop/restart revocation.
- Catalog tests: canonical IDs, restrictions, cached paging, no exposed URLs/metadata/stream resolution, idempotent favorites and shared channel-group membership.
- TV widget tests: opt-in and QR/code dialog sizing at 960x540.
- Existing universal search, dashboard remote navigation, channel-group and catalog My List regressions.

A physical phone/Fire TV pairing check is still required on the deployment network. Builds are not installed automatically.
