import 'package:get/get.dart';
import '../controllers/meeting_connect_controller.dart';

class MeetingConnectBinding extends Bindings {
  @override
  void dependencies() {
    // 注册控制器
    Get.lazyPut<MeetingConnectController>(() => MeetingConnectController());
  }
}
