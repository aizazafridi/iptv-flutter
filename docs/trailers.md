# In-app trailers

Movie and series Trailer actions route through `openInAppTrailer`.

- Recognized YouTube watch/share/embed/shorts links use the official IFrame Player API inside the operating system WebView. Strict host and 11-character ID validation prevents arbitrary page/script loading.
- Direct HTTP(S) MP4/M4V/MOV/WebM/HLS/DASH/TS links use Streamora's existing player, with no item or watch-history store attached. Trailer playback does not create a Continue Watching entry.
- Unsupported links and YouTube embedding/private/deleted/format/identity errors stay in Streamora with a readable message. There is no automatic YouTube app/browser fallback.
- Back/Esc returns to the originating details page and restores its focus. Play/Pause and 10-second seek buttons are outside the official embedded player; YouTube controls and branding remain visible.

## WebView identity and lifecycle

On Android, the local player document loads through `loadDataWithBaseURL` using the HTTPS app identity `https://com.iptv.iptv_flutter/trailer`; subresource requests stay in the native WebView rather than crossing the Flutter interception channel. On Windows, the WebView navigates to that identity and the exact main-frame request is fulfilled locally by `shouldInterceptRequest`. No public server is required. Using a real document origin rather than Windows `NavigateToString`/about:blank preserves the app-identity Referer required by YouTube (error 153). The player also declares the same origin/widget_referrer. The HTML contains no provider credentials or provider media URLs.

No YouTube stream extraction or private download API is used. External application schemes, arbitrary navigation, new windows and permission requests are blocked. Only recognized HTTPS YouTube origins and the local document origin may navigate inside the embed. Playback pauses when the application leaves the foreground. The platform view is released on route disposal, followed by its Windows environment.

Windows uses Microsoft Edge WebView2 and an application-support data folder. Missing runtime initialization produces an in-app error. Fire TV uses its system Android WebView; actual YouTube playback depends on the device WebView/network and the video's embedding availability. Physical Fire TV verification is required; widget tests do not prove network video playback.

## Build

The `flutter_inappwebview` plugin provides Android and Windows implementations. Its Windows build requires NuGet. If NuGet is absent from PATH, CMake downloads Microsoft NuGet 6.11.1 into the build directory with a pinned SHA-256 digest; no global tool installation is needed. The digest was checked against the downloaded Microsoft-signed executable. The stable Windows plugin remains on its C++17/WIL coroutine compatibility path, with the explicit MSVC deprecation opt-in scoped to that plugin. Its legacy source does not yet compile in strict C++20 mode. MSVC compilation uses /FS and a plugin-specific compiler PDB to prevent debug-symbol write collisions, including after interrupted builds. The Android platform package is locally vendored solely to select the optimize ProGuard default required by AGP 9.1; its Java and Dart sources are unchanged. Shared Pub-cache files are not modified.

## References

- https://developers.google.com/youtube/iframe_api_reference
- https://developers.google.com/youtube/terms/required-minimum-functionality
- https://inappwebview.dev/docs/intro/

## Checks

Unit/widget tests cover accepted and rejected source URLs, HTML identity and official controls, remote Play/Pause/seek, Back/Esc, and blocked embedding without external navigation. Existing movie and series details tests also run. A full application restart is required after installing the newly added native plugin.

## Playback stability

The YouTube route has no fade animation. The video viewport keeps its size during loading, playback, errors, and retry; progress events update bridge values without rebuilding Flutter. Android hardware acceleration and hybrid composition remain enabled. Initial loading and subsequent buffering have bounded timeouts, with a visible reload action and renderer-failure recovery. Reload invalidates callbacks from the old WebView. Physical Fire TV playback still needs verification after installation; widget tests cover viewport geometry and recovery state, not decoded video frames.

Android local-document identity follows https://developer.android.com/develop/ui/views/layout/webapps/load-local-content.
