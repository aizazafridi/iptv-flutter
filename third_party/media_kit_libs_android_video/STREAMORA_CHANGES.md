# Streamora caption-capable Android native library

Based on media_kit_libs_android_video 1.3.8; upstream license retained.
Only native artifact selection and checksum verification differ from upstream.

The original v1.1.7 default FFmpeg flavor disables decoders and omits cc_dec.
It can advertise eia_608 tracks while failing to open their decoder. The full
v1.1.8 flavor enables decoders, including cc_dec. v1.1.7 did not publish full
artifacts, so this uses the nearest subsequent release with full artifacts.

Artifacts are fetched from the official media-kit/libmpv-android-video-build
GitHub release and verified against pinned SHA-256 digests in android/build.gradle.
No binaries are committed. Do not change files in the shared Pub cache.

Sources:
- https://github.com/media-kit/libmpv-android-video-build/blob/v1.1.7/buildscripts/flavors/default.sh
- https://github.com/media-kit/libmpv-android-video-build/blob/v1.1.8/buildscripts/flavors/full.sh
- https://github.com/media-kit/libmpv-android-video-build/releases/tag/v1.1.8

Validation still requires actual captions on Fire TV; decoder inclusion alone
is not proof that a particular live feed carries decodable caption packets.
