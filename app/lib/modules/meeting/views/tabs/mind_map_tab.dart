import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../controllers/mind_map_controller.dart';

class MindMapTab extends StatefulWidget {
  const MindMapTab({super.key});

  @override
  State<MindMapTab> createState() => _MindMapTabState();
}

class _MindMapTabState extends State<MindMapTab>
    with AutomaticKeepAliveClientMixin {
  final _controller = Get.find<MindMapController>();

  // 缓存上一次的主题模式，用于检测变化
  Brightness? _lastBrightness;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentBrightness = Theme.of(context).brightness;
    // 仅在主题实际变化时通知控制器更新 WebView
    if (_lastBrightness != null && _lastBrightness != currentBrightness) {
      _controller.updateTheme();
    }
    _lastBrightness = currentBrightness;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      top: false,
      child: WebViewWidget(
        controller: _controller.webViewController,
      ),
    );
  }
}
