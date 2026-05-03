import 'package:get/get.dart';

import '../../../data/models/user_Info.dart';

/// Stubbed ProfileController for the ported meeting module.
///
/// The original implementation depends on local plugins and services that
/// are not available in `ai-agent-client`. The meeting module only needs
/// [userInfo] and [localAvatar].
class ProfileController extends GetxController {
  static ProfileController get to => Get.find();

  // The original used `User.instance.obs`. The stub provides a safe fallback
  // when the user singleton is not yet initialized.
  late final Rx<User> userInfo = (User.isLoggedIn()
          ? User.instance
          : User.empty())
      .obs;

  final RxString localAvatar = ''.obs;
  final RxBool isAvatarReady = true.obs;

  void loadUserInfo() {
    if (User.isLoggedIn()) {
      userInfo.value = User.instance;
    }
  }

  @override
  void onInit() {
    super.onInit();
    loadUserInfo();
  }
}
