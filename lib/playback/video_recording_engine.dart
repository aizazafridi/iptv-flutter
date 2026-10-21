abstract interface class VideoRecordingEngine {
  Future<void> startVideoRecording(String path);
  Future<void> stopVideoRecording();
}
