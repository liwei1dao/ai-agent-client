import 'dart:convert';
import 'dart:io';

import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../../../legacy_stubs/htmltopdfwidgets.dart' as pdf;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/utils/logger.dart';
import '../../../../data/services/network/dio_manager.dart';
import '../../controllers/meeting_details_controller.dart';
import '../../controllers/mind_map_controller.dart';
import 'second_level_bottom_sheet.dart';

/// ============================================================================
/// 分享底部弹窗组件
/// ============================================================================
/// 功能说明：
/// 本组件提供会议详情页面的分享功能入口，以底部弹窗形式展示8个核心功能：
/// 1. 分享链接 - 生成并分享会议网页链接
/// 2. 复制转写 - 将会议转写文本复制到剪贴板
/// 3. 复制总结 - 将会议总结内容复制到剪贴板
/// 4. 导出音频 - 分享会议录音文件
/// 5. 导出转写 - 将转写内容导出为TXT文件
/// 6. 导出总结 - 将总结内容导出为TXT或PDF文件
/// 7. 保存思维导图 - 将思维导图保存为图片到本地
/// 8. 分享思维导图 - 将思维导图以图片形式分享
///
/// 权限控制：
/// - 复制/导出转写功能需要 tasktype >= 3 且 tasktype < 10002
/// - 复制/导出/思维导图功能需要 tasktype >= 5 且 tasktype < 10001
/// ============================================================================

/// 思维导图操作类型常量
class _MindMapActionType {
  /// 保存到本地相册
  static const int save = 1;

  /// 分享给他人
  static const int share = 2;
}

/// 分享底部弹窗 - 有状态组件
/// 使用StatefulWidget以便在build方法中多次获取主题状态
class ShareBottomSheet extends StatefulWidget {
  const ShareBottomSheet({super.key});

  @override
  State<ShareBottomSheet> createState() => _ShareBottomSheetState();
}

class _ShareBottomSheetState extends State<ShareBottomSheet> {
  /// 会议详情控制器 - 通过GetX依赖注入获取
  /// 包含会议数据、转写列表、总结内容等核心数据
  final _controller = Get.find<MeetingDetailsController>();

  /// 获取分享弹出位置（iOS iPad需要）
  /// 多层兜底策略：控件真实位置 → 屏幕中心小矩形
  Rect _getSharePositionOrigin() {
    // 检查 mounted 状态，避免 context 已释放导致崩溃
    if (mounted) {
      try {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          return box.localToGlobal(Offset.zero) & box.size;
        }
      } catch (_) {
        // context 可能已失效，使用兜底方案
      }
    }
    // 兜底：屏幕中心小矩形，符合iOS交互规范
    return Rect.fromCenter(
      center: Offset(Get.width / 2, Get.height / 2),
      width: 1,
      height: 1,
    );
  }

  /// 是否有转写权限（tasktype >= 3 且 tasktype < 10002）
  bool get _hasTranscriptPermission {
    final tasktype = _controller.meetingDetails.value.tasktype;
    return tasktype >= 3 && tasktype < 10002;
  }

  /// 是否有总结权限（tasktype >= 5 且 tasktype < 10001）
  bool get _hasSummaryPermission {
    final tasktype = _controller.meetingDetails.value.tasktype;
    return tasktype >= 5 && tasktype < 10001;
  }

  /// 清理文件名中的非法字符
  /// 过滤 / \ : * ? " < > | 等文件系统不允许的字符
  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  }

  /// 处理思维导图操作（保存/分享）
  /// [actionType] 操作类型，使用 [_MindMapActionType] 常量
  ///
  /// iOS 特殊处理：
  /// WKWebView 在 tab 不可见时，JavaScriptChannel（ImageChannel）通信会被暂停，
  /// 导致 JS 的 postMessage 回调无法触发。
  /// 修复方案：操作前先切换到思维导图 tab（index=3），确保 WebView 可见后再执行截图。
  void _handleMindMapAction(int actionType) {
    Get.back();
    final mindMapController = Get.find<MindMapController>();
    final meetingController = Get.find<MeetingDetailsController>();
    mindMapController.imageType = actionType;

    // 思维导图 tab 的索引（TabBarView 第 4 个子项，index=3）
    const int mindMapTabIndex = 3;
    final bool isOnMindMapTab =
        meetingController.tabController.index == mindMapTabIndex;

    void runCapture() {
      if (mindMapController.isWebViewReady) {
        mindMapController.webViewController.runJavaScript('captureImage()');
      } else {
        // WebView 尚未加载完成，等待 onPageFinished 后执行
        mindMapController.webViewController.setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) {
              mindMapController.isWebViewReady = true;
              mindMapController.webViewController
                  .runJavaScript('captureImage()');
            },
          ),
        );
      }
    }

    if (Platform.isIOS && !isOnMindMapTab) {
      // iOS 上若当前不在思维导图 tab，先切换过去，确保 WKWebView 可见后再执行截图
      meetingController.tabController.animateTo(mindMapTabIndex);
      // 等待下一帧渲染完成后执行截图，避免 WebView 尚未完成布局
      WidgetsBinding.instance.addPostFrameCallback((_) {
        runCapture();
      });
    } else {
      runCapture();
    }
  }

  /// ==========================================================================
  /// 构建UI界面
  /// ==========================================================================
  /// 整体布局结构：
  /// - SafeArea: 适配刘海屏等异形屏幕
  /// - Padding: 水平方向12.w的内边距
  /// - Column: 垂直排列的弹性布局
  ///   ├─ 头部区域：会议标题 + 关闭按钮
  ///   └─ 功能列表区域：3个功能分组盒子
  ///       ├─ 第一组：分享链接
  ///       ├─ 第二组：复制转写、复制总结
  ///       └─ 第三组：导出音频、导出转写、导出总结、保存思维导图、分享思维导图
  /// ==========================================================================
  @override
  Widget build(BuildContext context) {
    // 获取当前主题模式（深色/浅色），用于UI颜色适配
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      // top: false 表示不保护顶部安全区域，让弹窗可以延伸到状态栏下方
      top: false,
      child: Padding(
        // 水平方向12.w的内边距，使用flutter_screenutil进行屏幕适配
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Column(
          // 主轴尺寸最小化，只占用内容所需高度
          mainAxisSize: MainAxisSize.min,
          children: [
            // ==================== 头部区域：会议标题栏 ====================
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Row(
                children: [
                  // 音频文件图标
                  Icon(
                    Icons.audio_file_outlined,
                    color: isDarkMode ? Colors.grey[500] : Colors.grey,
                    size: 32.w,
                  ),
                  5.horizontalSpace, // 5.w的水平间距
                  // 会议标题文本 - 从控制器获取
                  Expanded(
                    child: Text(
                      _controller.meetingData.value.title,
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  // 关闭按钮 - 点击后关闭底部弹窗
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      width: 26.w,
                      height: 26.w,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[700] : Colors.white,
                        borderRadius: BorderRadius.circular(26.r),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18.w,
                        color: Colors.grey[400],
                      ),
                    ),
                  )
                ],
              ),
            ),
            // ==================== 功能列表区域 ====================
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Column(
                children: [
                  // ------------------ 功能组1：分享链接 ------------------
                  _box([
                    _shareItem(
                      Icons.link,
                      'shareLink'.tr, // 对应中文：分享链接
                      isBorder: false,
                      // 【核心功能模块1：分享链接】
                      // 功能说明：生成会议分享链接并通过系统分享面板分享
                      // 执行流程：
                      // 1. 关闭底部弹窗
                      // 2. 从本地存储获取用户登录token
                      // 3. 获取会议ID和服务器地址
                      // 4. 构建分享URL格式：https://share.deepechomeet.com/share/{serverHost}/voitrans.net/{id}/{token}
                      // 5. 调用SharePlus分享链接
                      // 6. 分享成功后显示提示
                      onTap: () async {
                        // 在关闭弹窗前捕获分享位置（iPad需要）
                        final origin = _getSharePositionOrigin();
                        Get.back();
                        try {
                          final GetStorage storage = GetStorage();
                          String token = storage.read("logintoken") ?? '';
                          int id = _controller.meetingData.value.id;

                          // 获取动态服务器地址
                          final serverUrl = DioManager().baseUrl;
                          final serverHost = serverUrl
                              .replaceFirst('https://', '')
                              .replaceFirst('http://', '');

                          final result =
                              await SharePlus.instance.share(ShareParams(
                            title: _controller.meetingData.value.title,
                            subject:
                                'Voitrans WEB，由DeepSound.Ai提供支持-实时记录会议纪要，多语言翻译。',
                            uri: Uri.parse(
                              'https://share.deepechomeet.com/share/$serverHost/voitrans.net/$id/$token',
                            ),
                            sharePositionOrigin: origin,
                          ));
                          if (result.status == ShareResultStatus.success) {
                            EasyLoading.showToast(
                                'shareSuccess'.tr); // 对应中文：分享完成
                          }
                        } catch (e) {
                          Logger.error('分享链接失败: $e'); // 技术日志
                          EasyLoading.showToast(
                              'operationFailedPleaseRetry'.tr); // 对应中文：操作失败，请重试
                        }
                      },
                    ),
                  ]),
                  // ------------------ 功能组2：复制功能 ------------------
                  _box([
                    // 【核心功能模块2：复制转写】
                    // 功能说明：将会议所有转写文本复制到系统剪贴板
                    // 权限控制：仅当 tasktype >= 3 且 tasktype < 10002 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 调用 _getAllText() 获取格式化后的转写文本
                    // 4. 调用 _copy() 方法复制到剪贴板
                    // 数据格式：说话人 + 时间戳 + 内容
                    _shareItem(Icons.copy, 'copyTranscript'.tr, // 对应中文：复制转写
                        onTap: _hasTranscriptPermission
                            ? () {
                                Get.back();
                                _copy(_getAllText());
                              }
                            : null),
                    // 【核心功能模块3：复制总结】
                    // 功能说明：将会议总结内容复制到系统剪贴板
                    // 权限控制：仅当 tasktype >= 5 且 tasktype < 10001 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 调用 _markdownToPlainText() 将Markdown格式转为纯文本
                    // 4. 调用 _copy() 方法复制到剪贴板
                    _shareItem(Icons.copy, 'copySummary'.tr, // 对应中文：复制总结
                        isBorder: false,
                        onTap: _hasSummaryPermission
                            ? () {
                                Get.back();
                                _copy(_markdownToPlainText(
                                    _controller.meetingDetails.value.summary));
                              }
                            : null),
                  ]),
                  // ------------------ 功能组3：导出与分享功能 ------------------
                  _box([
                    // 【核心功能模块4：导出音频】
                    // 功能说明：分享会议录音音频文件
                    // 执行流程：
                    // 1. 点击后关闭底部弹窗
                    // 2. 调用 _share() 方法分享音频文件路径
                    // 参数说明：
                    // - filepath: 从 meetingData 获取的音频文件路径
                    // - title: 分享时显示的标题文本
                    _shareItem(
                        Icons.multitrack_audio, 'exportAudio'.tr, // 对应中文：导出音频
                        onTap: () async {
                      Get.back();
                      await _exportAudio();
                    }),
                    // 【核心功能模块5：导出转写】
                    // 功能说明：将转写内容导出为TXT文件并分享
                    // 权限控制：仅当 tasktype >= 3 且 tasktype < 10002 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 获取临时目录路径
                    // 4. 创建以会议标题命名的TXT文件
                    // 5. 调用 _getAllText() 获取转写内容并写入文件
                    // 6. 调用 _share() 方法分享文件
                    _shareItem(
                        Icons.message, 'exportTranscript'.tr, // 对应中文：导出转写
                        onTap: _hasTranscriptPermission
                            ? () async {
                                Get.back();
                                final tempDir = await getTemporaryDirectory();
                                final safeTitle = _sanitizeFileName(
                                    _controller.meetingData.value.title);
                                final file = File(
                                    '${tempDir.path}/${safeTitle}_speaker.txt');
                                String allText = _getAllText();
                                await file.writeAsString(allText,
                                    encoding: utf8);
                                _share(file.path,
                                    'exportTranscript'.tr); // 对应中文：分享会议转写
                              }
                            : null),
                    // 【核心功能模块6：导出总结】
                    // 功能说明：将总结内容导出为TXT或PDF格式
                    // 权限控制：仅当 tasktype >= 5 且 tasktype < 10001 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 弹出二级底部弹窗供用户选择导出格式（TXT/PDF）
                    // 4. 根据选择执行对应导出逻辑
                    //    - TXT: 创建临时文件，写入纯文本内容，调用 _share() 分享
                    //    - PDF: 调用 _exportMarkdownPdf() 方法生成PDF
                    _shareItem(Icons.article, 'exportSummary'.tr, // 对应中文：导出总结
                        onTap: _hasSummaryPermission
                            ? () async {
                                Get.back();
                                Get.bottomSheet(
                                  SecondLevelBottomSheet(
                                    'exportSummary'.tr, // 对应中文：导出总结
                                    'exportAs'.tr, // 对应中文：导出为
                                    // 回调函数：用户选择导出格式后的处理逻辑
                                    // 参数 index: 0=TXT, 1=PDF
                                    (int index) async {
                                      if (index == 0) {
                                        // 导出TXT格式
                                        final tempDir =
                                            await getTemporaryDirectory();
                                        final safeTitle = _sanitizeFileName(
                                            _controller
                                                .meetingData.value.title);
                                        final file = File(
                                            '${tempDir.path}/${safeTitle}_summary.txt');
                                        await file.writeAsString(
                                            _markdownToPlainText(_controller
                                                .meetingDetails.value.summary),
                                            encoding: utf8);
                                        _share(file.path,
                                            'exportSummary'.tr); // 对应中文：分享会议总结
                                      } else {
                                        // 导出PDF格式
                                        _exportMarkdownPdf();
                                      }
                                    },
                                    // 二级弹窗的选项配置
                                    const [
                                      {
                                        'icon': Icons.text_snippet,
                                        'title': 'TXT',
                                        'isBorder': true,
                                      },
                                      {
                                        'icon': Icons.picture_as_pdf,
                                        'title': 'PDF',
                                        'isBorder': false,
                                      },
                                    ],
                                  ),
                                  isScrollControlled: true,
                                  backgroundColor: isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.grey[100],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(12.r),
                                    ),
                                  ),
                                );
                              }
                            : null),
                    // 【核心功能模块7：保存思维导图】
                    // 功能说明：将思维导图保存为图片到本地相册
                    // 权限控制：仅当 tasktype >= 5 且 tasktype < 10001 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 设置 imageType = 1 表示保存操作
                    // 4. 检查WebView是否已加载完成
                    //    - 已就绪：直接执行 JavaScript 的 captureImage() 函数
                    //    - 未就绪：设置导航委托，在页面加载完成后执行
                    // 交互组件：与 MindMapController 和 WebView 协同工作
                    _shareItem(
                      Icons.save_alt,
                      'saveMindMap'.tr,
                      onTap: _hasSummaryPermission
                          ? () => _handleMindMapAction(_MindMapActionType.save)
                          : null,
                    ),
                    // 【核心功能模块8：分享思维导图】
                    // 功能说明：将思维导图以图片形式通过系统分享面板分享
                    // 权限控制：仅当 tasktype >= 5 且 tasktype < 10001 时可用
                    // 执行流程：
                    // 1. 检查权限条件，不满足则按钮置灰不可点击
                    // 2. 点击后关闭底部弹窗
                    // 3. 设置 imageType = 2 表示分享操作
                    // 4. 检查WebView是否已加载完成
                    //    - 已就绪：直接执行 JavaScript 的 captureImage() 函数
                    //    - 未就绪：设置导航委托，在页面加载完成后执行
                    // 交互组件：与 MindMapController 和 WebView 协同工作
                    // 注意：与保存思维导图的区别在于 imageType 的值不同，后续处理逻辑不同
                    _shareItem(
                      Icons.lan,
                      'shareMindMap'.tr, // 对应中文：分享思维导图
                      isBorder: false,
                      onTap: _hasSummaryPermission
                          ? () => _handleMindMapAction(_MindMapActionType.share)
                          : null,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ==========================================================================
  /// UI组件构建方法
  /// ==========================================================================

  /// 功能分组盒子组件
  /// 用于将相关的功能项组合在一起，提供统一的圆角和背景样式
  ///
  /// 参数说明：
  /// - children: 子组件列表，通常为多个 _shareItem
  ///
  /// 样式特性：
  /// - 底部外边距：10.w
  /// - 裁剪行为：硬边缘裁剪
  /// - 背景色：深色模式 #2D2D2D，浅色模式白色
  /// - 圆角半径：12.r
  Widget _box(List<Widget> children) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(bottom: 10.w),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  /// 分享功能项组件
  /// 单个功能按钮的UI封装，支持图标、标题、点击事件和禁用状态
  ///
  /// 参数说明：
  /// - icon: 功能图标（IconData类型）
  /// - title: 功能标题文本
  /// - isBorder: 是否显示底部边框，用于分隔多个功能项（默认true）
  /// - onTap: 点击回调函数，为null时按钮置灰不可点击
  ///
  /// 样式特性：
  /// - 水平内边距：12.w，垂直内边距：14.w
  /// - 禁用状态背景色：深色模式 grey[800]，浅色模式 grey[200]
  /// - 边框颜色：深色模式 grey[700]，浅色模式 grey[300]
  /// - 图标和文字透明度：启用状态1.0，禁用状态0.5
  Widget _shareItem(
    IconData icon,
    String title, {
    bool isBorder = true,
    VoidCallback? onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.w),
        decoration: BoxDecoration(
          color: onTap != null
              ? null
              : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
          border: isBorder
              ? Border(
                  bottom: BorderSide(
                    width: 0.5,
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            // 图标 - 根据启用状态调整透明度
            Opacity(
              opacity: onTap != null ? 1.0 : 0.5,
              child: Icon(
                icon,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            10.horizontalSpace, // 图标与文字间距
            // 标题文本 - 根据启用状态调整透明度
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: (isDarkMode ? Colors.white : Colors.black87)
                      .withValues(alpha: onTap != null ? 1 : 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ==========================================================================
  /// 核心功能方法
  /// ==========================================================================

  /// 导出音频方法
  /// 优先使用本地文件；本地不存在时尝试从云端下载，下载成功后继续分享
  ///
  /// 执行流程：
  /// 1. 检查本地文件是否存在 → 直接分享
  /// 2. 本地不存在 → 检查是否有云端 URL → 无 URL 则显示"文件不存在"
  /// 3. 有云端 URL → 显示加载提示并执行下载
  /// 4. 下载成功 → 继续分享；下载失败 → 显示"文件不存在"提示
  Future<void> _exportAudio() async {
    final filepath = _controller.meetingData.value.filepath;
    final audioUrl = _controller.meetingData.value.audiourl;

    // 本地文件存在，直接分享
    if (filepath.isNotEmpty && File(filepath).existsSync()) {
      _share(filepath, 'shareMeetingAudio'.tr); // 对应中文：分享会议音频
      return;
    }

    // 本地不存在，检查是否有云端 URL 可以下载
    if (audioUrl.isEmpty) {
      Logger.error('导出音频失败: 本地文件不存在且云端URL为空');
      EasyLoading.showToast('audioFileNotFound'.tr); // 对应中文：音频文件不存在
      return;
    }

    // 从云端下载
    EasyLoading.show(status: 'fetchingAudio'.tr); // 对应中文：正在从云端获取音频...
    final downloadedPath = await _controller.downloadAudioForShare();
    EasyLoading.dismiss();

    if (downloadedPath != null &&
        downloadedPath.isNotEmpty &&
        File(downloadedPath).existsSync()) {
      // 下载成功，继续分享
      _share(downloadedPath, 'shareMeetingAudio'.tr); // 对应中文：分享会议音频
    } else {
      // 下载失败，显示兜底提示
      Logger.error('导出音频失败: 云端下载失败 (url: $audioUrl)');
      EasyLoading.showToast('audioFileNotFound'.tr); // 对应中文：音频文件不存在
    }
  }

  /// 分享文件方法
  /// 使用 SharePlus 插件分享文件到系统分享面板
  ///
  /// 参数说明：
  /// - filepath: 要分享的文件的完整路径
  /// - title: 分享时显示的标题/描述文本
  ///
  /// 执行流程：
  /// 1. 构建 ShareParams 对象，包含文本和文件列表
  /// 2. 调用 SharePlus.instance.share() 触发系统分享
  /// 3. 检查分享结果状态，成功时显示提示
  ///
  /// 返回值：Future<void> - 异步操作
  Future<void> _share(String filepath, String title) async {
    try {
      // 检查文件路径是否为空或文件是否存在
      if (filepath.isEmpty || !File(filepath).existsSync()) {
        Logger.error('分享文件失败: 文件不存在 (path: $filepath)');
        EasyLoading.showToast('audioFileNotFound'.tr); // 对应中文：音频文件不存在
        return;
      }
      final result = await SharePlus.instance.share(ShareParams(
        text: title,
        files: [XFile(filepath)],
        sharePositionOrigin: _getSharePositionOrigin(),
      ));
      if (result.status == ShareResultStatus.success) {
        EasyLoading.showToast('shareSuccess'.tr); // 对应中文：分享完成！
      }
    } catch (e) {
      // 将错误信息合并到单条日志消息中，避免多行日志被截断
      Logger.error('分享文件失败 (path: $filepath, 错误: $e)');
      EasyLoading.showToast('operationFailedPleaseRetry'.tr); // 对应中文：操作失败，请重试
    }
  }

  /// 复制文本到剪贴板方法
  /// 使用 Flutter 的 Clipboard 服务将文本复制到系统剪贴板
  ///
  /// 参数说明：
  /// - text: 要复制的文本内容
  ///
  /// 执行流程：
  /// 1. 调用 Clipboard.setData() 设置剪贴板数据
  /// 2. 复制成功后显示 GetX Snackbar 提示
  ///
  /// 提示样式：
  /// - 标题：'success'.tr（成功）
  /// - 内容：'copySuccess'.tr（复制成功）
  /// - 背景色：蓝色半透明
  /// - 文字颜色：白色
  void _copy(String text) {
    Clipboard.setData(ClipboardData(
      text: text,
    )).then(
      (value) => Get.snackbar(
        'success'.tr, // 对应中文：成功
        'copySuccess'.tr, // 对应中文：复制成功
        backgroundColor: Colors.blue.withValues(alpha: 0.8),
        colorText: Colors.white,
      ),
    );
  }

  /// 将Markdown格式转换为纯文本
  /// 用于在复制或导出时将富文本格式转为纯文本，便于阅读和处理
  ///
  /// 参数说明：
  /// - markdown: Markdown格式的原始文本
  ///
  /// 返回值：String - 转换后的纯文本
  ///
  /// 转换规则：
  /// 1. 移除粗体标记 **text** 或 __text__
  /// 2. 移除斜体标记 *text* 或 _text_
  /// 3. 移除删除线标记 ~~text~~
  /// 4. 移除代码块标记 ```code```
  /// 5. 移除行内代码标记 `code`
  /// 6. 移除链接标记 [text](url)，保留文本
  /// 7. 移除图片标记 ![alt](url)，保留alt文本
  /// 8. 移除标题标记 # ## ### 等
  /// 9. 移除引用标记 >
  /// 10. 移除无序列表标记 - * +
  /// 11. 移除有序列表标记 1. 2. 等
  /// 12. 移除水平分割线 --- *** ___
  /// 13. 清理多余空行
  String _markdownToPlainText(String markdown) {
    String text = markdown;

    // 移除粗体标记 **text** 或 __text__
    text = text.replaceAllMapped(
        RegExp(r'\*\*(.*?)\*\*'), (match) => match.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'__(.*?)__'), (match) => match.group(1) ?? '');

    // 移除斜体标记 *text* 或 _text_
    text = text.replaceAllMapped(
        RegExp(r'\*(.*?)\*'), (match) => match.group(1) ?? '');
    text = text.replaceAllMapped(
        RegExp(r'_(.*?)_'), (match) => match.group(1) ?? '');

    // 移除删除线标记 ~~text~~
    text = text.replaceAllMapped(
        RegExp(r'~~(.*?)~~'), (match) => match.group(1) ?? '');

    // 移除代码块标记 ```code```
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '');

    // 移除行内代码标记 `code`
    text = text.replaceAllMapped(
        RegExp(r'`(.*?)`'), (match) => match.group(1) ?? '');

    // 移除链接标记 [text](url)
    text = text.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (match) => match.group(1) ?? '');

    // 移除图片标记 ![alt](url)
    text = text.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), (match) => match.group(1) ?? '');

    // 移除标题标记 # ## ### 等
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');

    // 移除引用标记 >
    text = text.replaceAll(RegExp(r'^>\s*', multiLine: true), '');

    // 移除列表标记 - * +
    text = text.replaceAll(RegExp(r'^[\s]*[-\*\+]\s+', multiLine: true), '');

    // 移除有序列表标记 1. 2. 等
    text = text.replaceAll(RegExp(r'^[\s]*\d+\.\s+', multiLine: true), '');

    // 移除水平分割线
    text =
        text.replaceAll(RegExp(r'^[\s]*[-\*_]{3,}[\s]*$', multiLine: true), '');

    // 清理多余的空行
    text = text.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');

    return text.trim();
  }

  /// 获取所有转写文本
  /// 将会议转写列表格式化为带说话人和时间戳的文本
  ///
  /// 返回值：String - 格式化后的完整转写文本
  ///
  /// 数据格式：
  /// 说话人 时间戳
  /// 内容
  ///
  /// 示例输出：
  /// 张三 09:30:15
  /// 大家好，会议开始。
  /// 李四 09:30:20
  /// 收到，请继续。
  ///
  /// 数据来源：
  /// - _controller.textList: 转写数据列表
  ///   - speaker: 说话人名称
  ///   - starttime: 开始时间戳（毫秒）
  ///   - content: 转写内容
  String _getAllText() {
    String text = '';
    for (var element in _controller.textList) {
      // 添加说话人信息（如果存在）
      if (element['speaker'].isNotEmpty) {
        text += '${element['speaker']} ';
      }
      // 添加格式化后的时间戳（UTC时间，HH:mm:ss格式）
      text += '${DateUtil.formatDateMs(
        element['starttime'],
        format: 'HH:mm:ss',
        isUtc: true,
      )}\n';
      // 添加转写内容
      text += '${element['content']}\n';
    }
    return text;
  }

  /// 获取资源文件的缩略图文件
  /// 将assets中的图片资源复制到临时目录，用于分享预览
  ///
  /// 参数说明：
  /// - assetPath: 资源文件在assets目录中的路径
  /// - fileName: 保存到临时目录的文件名
  ///
  /// 返回值：Future<XFile> - 临时文件的XFile对象
  ///
  /// 执行流程：
  /// 1. 使用 rootBundle.load() 加载资源文件字节数据
  /// 2. 获取应用临时目录
  /// 3. 创建目标文件并写入字节数据
  /// 4. 返回XFile对象供分享使用
  ///
  /// 注意：当前代码中此方法未被实际调用（注释状态）
  Future<XFile> getAssetThumbnailFile(String assetPath, String fileName) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return XFile(file.path);
  }

  /// 导出Markdown为PDF文件
  /// 将会议总结内容转换为PDF格式并分享
  ///
  /// 执行流程：
  /// 1. 显示加载提示 "正在导出PDF..."
  /// 2. 获取临时目录路径
  /// 3. 创建以会议标题命名的PDF文件
  /// 4. 使用 htmltopdfwidgets 插件将Markdown转换为PDF组件列表
  ///    - 加载 NotoSansSC 字体以支持中文显示
  /// 5. 创建PDF文档并添加多页内容
  /// 6. 保存PDF文件到临时目录
  /// 7. 调用 _share() 方法分享PDF文件
  /// 8. 关闭加载提示
  ///
  /// 依赖组件：
  /// - htmltopdfwidgets: 用于Markdown到PDF的转换
  /// - NotoSansSC-Regular.ttf: 中文字体资源
  ///
  /// 返回值：Future<void> - 异步操作
  Future<void> _exportMarkdownPdf() async {
    EasyLoading.show(status: 'exportingPDF'.tr); // 对应中文：正在导出PDF...
    try {
      final tempDir = await getTemporaryDirectory();
      final safeTitle = _sanitizeFileName(_controller.meetingData.value.title);
      final file = File('${tempDir.path}/${safeTitle}_summary.pdf');
      final List<pdf.Widget> markdownWidgets =
          await pdf.HTMLToPdf().convertMarkdown(
        _controller.meetingDetails.value.summary,
        fontFallback: [
          pdf.Font.ttf(
              await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf')),
        ],
      );
      final markdownPdf = pdf.Document();
      markdownPdf.addPage(pdf.MultiPage(
        build: (context) => markdownWidgets,
      ));
      await file.writeAsBytes(await markdownPdf.save());
      await _share(file.path, 'exportSummary'.tr); // 对应中文：分享会议总结
    } catch (e) {
      Logger.error('导出PDF失败: $e'); // 技术日志
      EasyLoading.showToast('operationFailedPleaseRetry'.tr); // 对应中文：操作失败，请重试
    } finally {
      EasyLoading.dismiss();
    }
  }
}
