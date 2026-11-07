# Sports Hub graphics update

The hub keeps TheSportsDB metadata, CricketData enrichment, existing profile favorites and existing IPTV playback. No generic sports channel list has been reintroduced.

- Static stadium header: assets/sports/stadium_header.jpg, 960 x 320 JPEG, approximately 45 KB. Decoded once with explicit size limits, bundled rather than downloaded. Reused across sports and never instantiated in Lite Mode. No per-card backdrop images or blur.
- Cards: two columns at TV widths, gradient panels, small blue focus glow, distinct fresh provider-confirmed LIVE badges, team identities and separate score columns. Cricket innings and overs are on separate lines; multiple innings are retained. Missing artwork uses initials, not inferred national flags. Team images come from actual TheSportsDB fields or CricketData teamInfo, including correctly reversed score/team-image mapping.
- Entire card: OK opens details. Down reaches secondary actions, Left/Right moves between actions; Up returns to the card. Focus/scroll restoration survives detail routes and score refresh. Cards keep fixed extents to avoid image-driven layout shifts.
- Follow uses actual primary team IDs. Supplemental events without primary IDs offer Find Teams instead of persisting invented IDs.
- Watch Live is shown only for a fresh live match after explicit Find Channels discovery has returned EPG-verified channel evidence. Possible/related channels never unlock this shortcut. Existing access checks and playback are reused.
- Coverage limitations remain available through the compact Coverage info action. Provider update time, when available, stays separate from fetched age; no invented Updated just now labels.
- Lite remains text-only without the hero image, team logos, card scale animation or glow.

Files: lib/presentation/sports_match_graphics.dart, lib/presentation/sports_hub_screen.dart, lib/domain/live_score.dart, lib/domain/sports.dart, lib/data/development_live_scores.dart, pubspec.yaml, assets/sports/stadium_header.jpg. Tests: test/sports_graphics_test.dart and updated test/sports_hub_test.dart, plus existing score/data suites.

## Generated asset provenance

Used the built-in image_gen tool through the imagegen skill, not CLI fallback. The original generated PNG stays in the tool output location; a project-local 960 x 320 optimized JPEG is the only asset referenced by the application. Header prompt:

> Create a single photorealistic panoramic sports stadium background asset for a television sports dashboard, no text, no logos, no UI, no players. Night stadium under blue-white floodlights, realistic grass pitch along the bottom, curved grandstands in the distance, subtle blue atmospheric light, dark navy overall grading. Wide landscape 3:1 composition, darker low-detail left two thirds for readable interface labels, brighter detailed stadium lights on the far right. Suitable across cricket and football; do not include a ball so it remains neutral across sports. Static premium sports broadcast atmosphere. Output a landscape image.

Physical Fire TV testing and installation were not performed for this visual update.
