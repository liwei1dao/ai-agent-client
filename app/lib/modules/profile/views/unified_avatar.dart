import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../controllers/profile_controller.dart';

/// 统一头像显示组件
/// 确保所有页面的头像显示逻辑一致，避免闪烁问题
class UnifiedAvatar extends StatelessWidget {
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final bool isDarkMode;
  final VoidCallback? onTap;

  const UnifiedAvatar({
    super.key,
    required this.radius,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.isDarkMode = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ProfileController profileCtrl = Get.find<ProfileController>();

    return GestureDetector(
      onTap: onTap,
      child: Obx(() {
        // 等待头像数据准备完成，避免闪烁
        if (!profileCtrl.isAvatarReady.value) {
          return _buildLoadingAvatar();
        }

        return _buildAvatar(profileCtrl);
      }),
    );
  }

  /// 构建加载中的头像占位符
  Widget _buildLoadingAvatar() {
    return CircleAvatar(
      radius: radius,
      backgroundColor:
          backgroundColor ?? (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
      child: Icon(
        Icons.person,
        size: iconSize ?? (radius * 0.6),
        color: iconColor ?? (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
      ),
    );
  }

  /// 构建实际头像
  Widget _buildAvatar(ProfileController profileCtrl) {
    ImageProvider<Object>? imageProvider;

    // 统一头像显示优先级：本地头像 > 网络头像 > 默认图标
    if (profileCtrl.localAvatar.value.isNotEmpty) {
      imageProvider = FileImage(File(profileCtrl.localAvatar.value));
    } else if (profileCtrl.userInfo.value.avatar.isNotEmpty) {
      imageProvider = NetworkImage(profileCtrl.userInfo.value.avatar);
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: imageProvider,
      backgroundColor:
          backgroundColor ?? (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
      child: (profileCtrl.localAvatar.value.isEmpty &&
              profileCtrl.userInfo.value.avatar.isEmpty)
          ? Icon(
              Icons.person,
              size: iconSize ?? (radius * 0.6),
              color: iconColor ??
                  (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
            )
          : null,
    );
  }
}

/// 带容器装饰的统一头像组件
class UnifiedAvatarWithContainer extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color? backgroundColor;
  final Color? iconColor;
  final double? iconSize;
  final bool isDarkMode;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? boxShadow;

  const UnifiedAvatarWithContainer({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
    this.backgroundColor,
    this.iconColor,
    this.iconSize,
    this.isDarkMode = false,
    this.onTap,
    this.margin,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: UnifiedAvatar(
          radius: radius / 2,
          backgroundColor: backgroundColor,
          iconColor: iconColor,
          iconSize: iconSize,
          isDarkMode: isDarkMode,
          onTap: onTap,
        ),
      ),
    );
  }
}
