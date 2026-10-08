# Streamlane

Flutter IPTV app for Android, iOS, and Android-based Fire TV, with Windows scaffolding for local development. Python sources remain in `C:/iptv`.

## Run

The Flutter SDK is local to `.tooling/flutter` (no global PATH changes).

```powershell
.\.tooling\flutter\bin\flutter.bat pub get
.\.tooling\flutter\bin\flutter.bat run --dart-define-from-file=config.dev.json
```

`config.dev.json` is ignored by Git and contains the existing development account. Debug builds use these defines to connect automatically when there is no saved account. Never distribute a build with development credentials: release builds ignore the development config, but Dart defines can still be embedded in a binary. Build releases without this flag.

New users enter server, username, password, and provider once. Credentials are stored using platform secure storage; the app reconnects on subsequent launches. Sign out clears saved credentials. No IPTV content is bundled.

## Architecture

* `domain/`: typed models and `IptvProvider` contract, independent of API implementations.
* `data/xtream/`: authenticated transport, response size limits, response mapping, playback URL resolution.
* `data/starshare/`: Starshare adapter built on the Xtream implementation.
* `application/`: provider registry and session lifecycle.
* `presentation/`: responsive screens, focusable touch/D-pad navigation, details and episode selection.
* `playback/`: separate player interface and media_kit adapter; no provider JSON or credentials in player controls.

To add another API, implement `IptvProvider`, map its data to domain models, declare its supported content types, and register it with `registry.register(id, label, builder)`. Existing screens and playback components need no changes. Provider-specific features can extend capabilities rather than adding provider-name checks to screens.

Movie/series cards open details on a tap or remote Select. Wide views have a left category sidebar and right content grid; phones navigate between lists. Series details offer season and episode selection. Player controls include pause/resume, 10-second seeking, a scrubber, fullscreen, and media remote keys. Back exits fullscreen first; leaving playback disposes the player. Playback errors never expose authenticated URLs.

## Validate

```powershell
.\.tooling\flutter\bin\flutter.bat analyze
.\.tooling\flutter\bin\flutter.bat test
.\.tooling\flutter\bin\flutter.bat doctor -v
```

Tests cover API mapping/authentication, episodes, URL escaping, large responses, and category/detail navigation without contacting the IPTV service.

Provider-only tests can also run independently of Flutter's rendering tools:

```powershell
.\.tooling\flutter\bin\dart.bat run test test/provider_test.dart
```

Initial validation on this Windows machine: Flutter static analysis passed; five standalone provider tests passed. Flutter widget tests were blocked by Windows Application Control refusing `impellerc.exe` (shader compiler), so GUI/device playback is not yet validated. Android SDK/Java are not installed. No release APK, AAB, or IPA has been produced. Resolve the local tooling requirements before device testing and store packaging; security settings were not changed by this project.

## Platform builds

* Android: install Android Studio/SDK and accept licenses; then `flutter build apk` or `flutter build appbundle`.
* Fire TV: Android manifest includes leanback launcher support, optional touchscreen, and a TV banner. Test focus, Back, media keys, codecs, and performance on a real Fire TV. An Android APK is used for Amazon distribution; this has not been submitted or certified.
* iOS: build on macOS with Xcode, CocoaPods, a signing team and a real device. Run `flutter build ios` there. Windows cannot build an iOS release.
* Windows preview: requires Visual Studio's Desktop development with C++ workload.

Replace the development application ID `com.iptv.iptv_flutter`, launcher icons, and banner before store submission. Configure release signing and product-specific privacy/account policies. HTTP IPTV servers are supported via Android cleartext and iOS transport settings; prefer HTTPS where offered. iOS secure storage requires the included keychain entitlement, and Android backup is disabled to avoid restoring encrypted credentials without their keys.

Dependencies: [media_kit](https://pub.dev/packages/media_kit), [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage). Store packaging, DRM streams, live EPG, watch history, subtitles/track selection UI, and download/offline playback are outside this initial version.

## Catalog search

Use the search icon at the top of Movies or Series to search every category. The provider loads the full catalog once per search visit, then filters titles locally, ignoring case and matching all entered words. Results open the usual details and player. The category-local search remains available. Future providers implement `getAllItems(ContentType)` to support catalog search.

Actor search matches title and cast across the catalog. When cast is absent from list responses, two background workers fetch details and update results progressively. Progress and Pause/Continue controls distinguish partial from complete actor results; failed requests can be retried. Cast is cached for the provider session, including titles already opened in details. The first pass can take time on large catalogs, and actor names unavailable from the provider cannot be matched. Leaving search stops scheduling further metadata requests.
