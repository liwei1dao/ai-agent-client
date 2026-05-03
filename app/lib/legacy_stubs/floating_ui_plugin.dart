/// Stub of `floating_ui_plugin` for the legacy meeting module port.
class NativePlugin {
  NativePlugin();

  Future<bool> showRecordingFloatingBar({
    required String duration,
    required String recordingType,
    bool isPaused = false,
  }) async =>
      false;

  Future<void> updateRecordingFloatingBar({
    required String duration,
    required String recordingType,
    bool isPaused = false,
  }) async {}

  Future<void> hideRecordingFloatingBar() async {}

  Stream<String> get recordingFloatingActionStream => const Stream.empty();
}
