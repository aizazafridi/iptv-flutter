import 'package:flutter/foundation.dart';
import '../data/video_recordings.dart';
import '../domain/models.dart';
import '../playback/video_recording_engine.dart';

class VideoRecorder extends ChangeNotifier {
  final VideoRecordingEngine engine;
  final VideoRecordings store;
  final ContentItem item;
  final String title;
  VideoRecorder({
    required this.engine,
    required this.store,
    required this.item,
    required this.title,
  });
  String? id;
  bool busy = false;
  DateTime? started;
  bool get recording => id != null;
  Future<void>? _operation;
  Future<void> toggle() {
    if (busy) return _operation ?? Future.value();
    busy = true;
    notifyListeners();
    return _operation = _toggle().whenComplete(() {
      busy = false;
      notifyListeners();
    });
  }

  Future<void> _toggle() async {
    if (id == null) {
      final reserved = await store.reserve();
      try {
        final path = (await store.file(reserved)).path;
        await engine.startVideoRecording(path);
        id = reserved;
        started = DateTime.now();
      } catch (_) {
        await store.discard(reserved);
        rethrow;
      }
    } else {
      final savedId = id!;
      try {
        await engine.stopVideoRecording();
        id = null;
        await store.finish(
          savedId,
          item,
          title,
          DateTime.now().difference(started!),
        );
      } catch (_) {
        id = null;
        await store.discard(savedId);
        rethrow;
      }
    }
  }

  Future<void> close() async {
    if (_operation != null) {
      try {
        await _operation;
      } catch (_) {}
    }
    if (recording) await toggle();
  }
}
