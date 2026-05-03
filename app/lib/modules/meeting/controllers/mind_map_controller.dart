import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../../../legacy_stubs/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'meeting_details_controller.dart';

/// 思维导图控制器
class MindMapController extends GetxController {
  late final WebViewController webViewController;
  final _meetingDetailsController = Get.find<MeetingDetailsController>();
  final double _width = 1.sw - 25.w;
  bool isWebViewReady = false;

  int imageType = 1;

  late final Worker _summaryNumberListener;

  @override
  void onInit() {
    super.onInit();
    String html = '''
<!DOCTYPE html>
<html lang="en">

<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>MindMap</title>
  <script>${_meetingDetailsController.markmapLibJs}</script>
  <script>${_meetingDetailsController.d3Js}</script>
  <script>${_meetingDetailsController.markmapViewJs}</script>
  <script>${_meetingDetailsController.markmapToolbarJs}</script>
  <script>${_meetingDetailsController.saveSvgAsPngJs}</script>
  <style>
    :root {
      --bg-color: #FFFFFF;
      --text-color: #000000;
      --toolbar-bg: #FFFFFF;
      --toolbar-border: #d0d5dd;
      --toolbar-text: #101828;
      --toolbar-active: #d4d4d8;
    }

    html,
    body {
      width: 100%;
      height: 100%;
      min-width: ${_width}px;
      min-height: ${_width}px;
      margin: 0;
      padding: 0;
      overflow: hidden;
      background-color: var(--bg-color);
      transition: background-color 0.3s ease;
    }

    .mind-map {
      width: 100%;
      height: 100%;
      position: relative;
      overflow: hidden;
    }

    .mind-map #markmap {
      width: 100%;
      height: 100%;
    }

    .mind-map #markmap .markmap-node-text {
      fill: var(--text-color) !important;
      transition: fill 0.3s ease;
    }

    .mind-map .mm-toolbar {
      height: 30px;
      background: var(--toolbar-bg);
      border: 1px solid var(--toolbar-border);
      border-radius: 8px;
      display: flex;
      justify-content: space-around;
      align-items: center;
      position: absolute;
      top: 10px;
      right: 2px;
      transition: background 0.3s ease, border-color 0.3s ease;
    }

    .mind-map .mm-toolbar-item {
      width: 24px;
      height: 24px;
      border-radius: 6px;
      cursor: pointer;
      color: var(--toolbar-text);
      display: flex;
      justify-content: center;
      align-items: center;
      transition: color 0.3s ease;
    }

    .mind-map .mm-toolbar-item.active {
      background-color: var(--toolbar-active);
    }
  </style>
</head>

<body>
  <div class="mind-map">
    <svg id="markmap"></svg>
    <div id="toolbar"></div>
  </div>
  <script>
    const { Transformer, Markmap, Toolbar } = window.markmap;
    const transformer = new Transformer();
    const { root } = transformer.transform(`${_meetingDetailsController.meetingDetails.value.summary}`);
    let mm = Markmap.create('#markmap', {
      maxWidth: 300,
      initialExpandLevel: 3,
    }, root);
    const toolbar = Toolbar.create(mm);
    toolbar.showBrand = false;
    // 只保留放大、缩小、适配窗口、递归展开；移除自带的 dark 按钮
    toolbar.setItems(['zoomIn', 'zoomOut', 'fit', 'recurse']);
    toolbar.render();
    const el = toolbar.el;
    const toolbarElement = document.getElementById('toolbar');
    toolbarElement.append(el);

    window.updateMarkmap = async function(value) {
      const { root } = transformer.transform(value);
      await mm.setData(root);
      await mm.fit();
    }

    // 动态切换主题颜色
    window.updateTheme = function(isDark) {
      const r = document.documentElement;
      if (isDark) {
        // 确保 markmap 内部暗色样式与 App 暗色主题一致
        r.classList.add('markmap-dark');
        r.style.setProperty('--bg-color', '#121212');
        r.style.setProperty('--text-color', '#FFFFFF');
        r.style.setProperty('--toolbar-bg', '#2D2D2D');
        r.style.setProperty('--toolbar-border', '#404040');
        r.style.setProperty('--toolbar-text', '#FFFFFF');
        r.style.setProperty('--toolbar-active', '#404040');
      } else {
        // 还原为浅色主题
        r.classList.remove('markmap-dark');
        r.style.setProperty('--bg-color', '#FFFFFF');
        r.style.setProperty('--text-color', '#000000');
        r.style.setProperty('--toolbar-bg', '#FFFFFF');
        r.style.setProperty('--toolbar-border', '#d0d5dd');
        r.style.setProperty('--toolbar-text', '#101828');
        r.style.setProperty('--toolbar-active', '#d4d4d8');
      }
      // 保存当前主题用于截图
      window._isDarkTheme = isDark;
    }

    window.captureImage = async function() {
      const markmapElement = document.getElementById('markmap');
      markmapElement.style.height = `${_width}px`;
      await mm.fit();
      const bgColor = window._isDarkTheme ? '#121212' : '#FFFFFF';
      const options = {
        scale: 2,
        backgroundColor: bgColor,
        encoderOptions: 1,
      };
      const uri = await svgAsPngUri(markmapElement, options);
      markmapElement.style.height = '100%';
      mm.fit();
      if (window.ImageChannel) {
        window.ImageChannel.postMessage(uri);
      }
    }
  </script>
</body>

</html>
    ''';
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            isWebViewReady = true;
            // 页面加载完成后立即应用当前主题
            _applyCurrentTheme();
          },
        ),
      )
      ..addJavaScriptChannel(
        'ImageChannel',
        onMessageReceived: _messageReceived,
      )
      ..setBackgroundColor(Colors.transparent)
      ..loadHtmlString(html);
    _summaryNumberListener =
        ever(_meetingDetailsController.summaryNumberModifications, (value) {
      webViewController.runJavaScript(
          'updateMarkmap(`${_meetingDetailsController.meetingDetails.value.summary}`)');
    });
  }

  /// 应用当前主题到 WebView
  void _applyCurrentTheme() {
    if (!isWebViewReady) return;
    final isDark = Get.isDarkMode;
    webViewController.runJavaScript('updateTheme($isDark)');
  }

  /// 供外部调用的主题更新方法
  void updateTheme() {
    _applyCurrentTheme();
  }

  @override
  void onClose() {
    _summaryNumberListener.dispose();
    super.onClose();
  }

  void _messageReceived(message) async {
    final String dataUrl = message.message;
    final String base64Str = dataUrl.split(',').last;
    final Uint8List bytes = base64.decode(base64Str);
    if (imageType == 1) {
      // 保存图片
      final result = await ImageGallerySaverPlus.saveImage(
        bytes,
        quality: 100,
      );
      if (result['isSuccess']) {
        EasyLoading.showToast('saveSuccess'.tr);
      }
    } else {
      // 分享图片
      final String fileName =
          '${_meetingDetailsController.meetingData.value.title}_mindmap.png';
      final tempDir = await getTemporaryDirectory();
      final File file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      final result = await SharePlus.instance.share(ShareParams(
        text: 'shareMindMap'.tr, //对应中文：分享思维导图
        files: [XFile(file.path)],
      ));
      if (result.status == ShareResultStatus.success) {
        EasyLoading.showToast('shareSuccess'.tr); //对应中文：分享成功
      }
    }
  }
}
