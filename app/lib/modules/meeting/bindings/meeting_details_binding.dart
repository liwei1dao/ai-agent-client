import 'package:get/get.dart';
import '../controllers/meeting_details_controller.dart';
import '../controllers/mind_map_controller.dart';

class MeetingDetailsBinding extends Bindings {
  /// 调用方在 push 之前显式注入会议 id，避免依赖 GetX 的 `Get.arguments`
  /// —— 我们在 GoRouter routerDelegate 模式下，`Get.to(arguments:)` 不会
  /// 正确写入 `Get.routing.args`，必须显式传。
  MeetingDetailsBinding({this.id = 0});

  final int id;

  @override
  void dependencies() {
    // 用 fenix=false 不影响；每次进详情页都拿最新 id 重建 controller。
    Get.delete<MeetingDetailsController>(force: true);
    Get.delete<MindMapController>(force: true);
    Get.lazyPut<MeetingDetailsController>(
        () => MeetingDetailsController(injectedId: id));
    Get.lazyPut<MindMapController>(() => MindMapController());
  }
}
