import 'package:get/get.dart';

import '../../../data/services/asr_service.dart';
import '../../../data/services/ble_manager.dart';
import '../../../data/services/meeting/meeting_task_service.dart';
import '../../../data/services/meeting/meeting_upload_service.dart';
import '../../../data/services/usage_stats_service.dart';
import '../../profile/controllers/profile_controller.dart';
import '../controllers/meeting_controller.dart';
import '../controllers/meeting_home_controller.dart';
import '../controllers/meeting_mine_controller.dart';

class MeetingBinding extends Bindings {
  @override
  void dependencies() {
    // 全局服务（保留单例 + fenix=true 重新生成；与源项目 InitialBinding 一致）
    if (!Get.isRegistered<UsageStatsService>()) {
      Get.put<UsageStatsService>(UsageStatsService(), permanent: true);
    }
    if (!Get.isRegistered<BleManager>()) {
      Get.put<BleManager>(BleManager(), permanent: true);
    }
    if (!Get.isRegistered<AsrService>()) {
      Get.put<AsrService>(AsrService(), permanent: true);
    }
    if (!Get.isRegistered<MeetingTaskService>()) {
      Get.lazyPut<MeetingTaskService>(() => MeetingTaskService(),
          fenix: true);
    }
    if (!Get.isRegistered<MeetingUploadService>()) {
      Get.lazyPut<MeetingUploadService>(() => MeetingUploadService(),
          fenix: true);
    }

    // 页面控制器
    Get.lazyPut<MeetingController>(() => MeetingController());
    Get.lazyPut<MeetingHomeController>(() => MeetingHomeController());
    Get.lazyPut<MeetingMineController>(() => MeetingMineController());
    Get.lazyPut<ProfileController>(() => ProfileController());
  }
}
