# Smooth remote navigation

Catalog rails focus mounted neighbours immediately within the active row, so outgoing and incoming focus animations overlap instead of waiting for scrolling to finish. Cross-row and off-screen navigation still waits for lazy children to attach. Retargeted scrolls track their destination and generation, avoiding duplicate animation restarts and stale completion updates during rapid input.

Horizontal/vertical catalog scrolling uses 280 ms ease-out cubic transitions. Poster width, border, dashboard and detail focus transitions use 240 ms; common card/button focus transitions use matching timing. Horizontal scroll respects reduced-motion settings. Logical navigation, category ordering, playback and authentication remain unchanged.

Validation: Flutter analysis clean; 45 relevant tests pass, including rapid directional input while scrolling, latest-target focus, first-tile row entry, details return focus and movie/series sizing. Physical-device smoothness is not benchmarked; the update is installed without launching the app.
