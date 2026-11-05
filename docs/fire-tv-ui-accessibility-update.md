# Fire TV UI update

- Movie More Settings now requests focus on the normal-speed control (or seek when speed is unavailable). Applying a setting preserves remote focus.
- Live My List group chips use the category-tab colors, radius, text size and blue focus border.
- Save to My List is compact. Add/edit profile forms use smaller text, fields, avatars and buttons, with scrolling retained for small displays.
- Movie and series primary Play/Resume actions share width, height, text sizing and padding.
- Category search keeps its query when moving to results. Done/Down reaches matching categories; Up returns to the input. Channel search also has a direct header button and filters the current category/My List.
- Movies/series catalog cards grow to 1.07 on focus with the existing 170 ms animation.
- Guide EPG downloads are limited to two lanes, and rows outside the visible guide viewport are not eagerly built. The active video engine/surface is preserved. Live playback no longer inherits a saved VOD slow/fast playback rate; VOD still restores its saved speed.
- Profile startup warms the disk cache for up to eight movies and eight series, prioritizing watch history, My List, then recent titles. Four workers share the existing artwork repository/variants and stop scheduling after a five-second budget. No cast/catalog-wide preload is added. Lite Mode makes no artwork requests. Unavailable images can still show placeholders; this cannot guarantee every catalog card has an image.

Validation: clean Flutter analysis. 67 relevant regression tests passed, followed by two additional saved-speed tests plus the existing guide/focus checks (all six passed). Tests cover remote focus, typed category search, startup budget/dedup/concurrency/Lite behavior, guide engine continuity, movie/series details and profile editing.

Physical Fire TV navigation and guide smoothness still require device verification. No device measurements or speed improvement claims are made. The release APK is built locally; no installation or launch is performed for this update.
