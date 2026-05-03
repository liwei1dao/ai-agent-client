import 'package:get/get.dart';
import '../controllers/meeting_record_controller.dart';

/// 录音模块依赖绑定类
class MeetingRecordBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<MeetingRecordController>()) {
      Get.put<MeetingRecordController>(MeetingRecordController(),
          permanent: true);
    }
  }
}
