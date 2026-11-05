import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A single Android audio-focus owner for the entire Multi View experience.
/// Decoder counts are diagnostics only, never a promise of playable streams.
class MultiviewPlatform {
  static const channel = MethodChannel('streamora/multiview');
  final void Function(bool interrupted) onAudioInterruption;
  MultiviewPlatform(this.onAudioInterruption);
  bool active = true;
  String? decoderSummary;
  bool get android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> initialize() async {
    if (!android) return;
    channel.setMethodCallHandler((call) async {
      if (active && call.method == 'audioFocus') {
        onAudioInterruption(call.arguments != true);
      }
    });
    try {
      final data = await channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      if (!active) return;
      final decoders = (data?['decoders'] as List? ?? []).whereType<Map>();
      final limits = decoders
          .map((row) => '${row['mime']}: ${row['instances']}')
          .toSet()
          .take(4)
          .join(', ');
      decoderSummary = limits.isEmpty
          ? null
          : 'Reported codec instance upper bounds: $limits';
    } catch (_) {
      /* Desktop and older installations can still use Multi View. */
    }
    if (active) await acquire();
  }

  Future<void> acquire() async {
    if (!android || !active) return;
    try {
      final granted = await channel.invokeMethod<bool>('requestAudioFocus');
      if (active) onAudioInterruption(granted != true);
    } catch (_) {
      /* Existing engine audio policy remains the fallback. */
    }
  }

  Future<void> release() async {
    if (!android) return;
    try {
      await channel.invokeMethod<void>('abandonAudioFocus');
    } catch (_) {}
  }

  void dispose() {
    active = false;
    if (android) channel.setMethodCallHandler(null);
    release();
  }
}
