import 'package:get/get.dart';

/// Stubbed BLE manager. The original was backed by a custom BLE plugin
/// which is not available in `ai-agent-client`.
class BleManager extends GetxService {
  static BleManager get to => Get.find();

  bool get isConnected => false;
  RxBool get isConnectedRx => false.obs;

  void openCodec() {}
  void closeCodec() {}
  void openEncoder() {}
  void openDecoder() {}
  void openCallRecordDecoder() {}
}
