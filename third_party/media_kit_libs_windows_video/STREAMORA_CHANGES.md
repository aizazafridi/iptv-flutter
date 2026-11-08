Windows caption decoder fix

Based on media_kit_libs_windows_video 1.0.11 (MIT license retained). Uses the standard x86_64 upstream shinchiro libmpv development build dated 20261108, not the v3 CPU variant. This includes FFmpeg cc_dec omitted from the original media-kit DLL. The release archive and unchanged ANGLE archive are pinned with SHA-256. A versioned extraction directory prevents reusing the old decoder. No binaries are committed. Native-library changes require a full application restart.

Source: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/20261108

Offline validation: identical local Scenarist SCC/EIA-608 sample plus silent WAV, using libmpv directly without a provider connection. Original DLL: sid=no and no decoded text. Replacement DLL: sid=1 and nonempty sub-text. This validates the decoder; actual CNN HD caption packets still require playback verification.
