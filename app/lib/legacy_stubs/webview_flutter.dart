/// Stub of `webview_flutter` for the legacy meeting module port.
///
/// The webview is replaced with an empty placeholder widget. The stub keeps
/// just enough API surface to satisfy callers in the meeting module.
import 'dart:async';

import 'package:flutter/widgets.dart';

class WebViewController {
  WebViewController();

  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  Future<void> loadRequest(Uri uri) async {}
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
  Future<void> setNavigationDelegate(NavigationDelegate delegate) async {}
  Future<void> setBackgroundColor(Color color) async {}
  Future<dynamic> runJavaScriptReturningResult(String javaScript) async => '';
  Future<void> runJavaScript(String javaScript) async {}
  Future<void> reload() async {}
  Future<void> clearCache() async {}
  Future<String?> currentUrl() async => null;
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage) onMessageReceived,
  }) async {}
}

enum JavaScriptMode { unrestricted, disabled }

class NavigationDelegate {
  NavigationDelegate({
    void Function(int)? onProgress,
    void Function(String)? onPageStarted,
    void Function(String)? onPageFinished,
    void Function(WebResourceError)? onWebResourceError,
    NavigationDecision Function(NavigationRequest)? onNavigationRequest,
  });
}

class WebResourceError {
  String description = '';
  int? errorCode;
}

enum NavigationDecision { navigate, prevent }

class NavigationRequest {
  String url = '';
  bool isMainFrame = true;
}

class JavaScriptMessage {
  final String message;
  JavaScriptMessage(this.message);
}

class WebViewWidget extends StatelessWidget {
  final WebViewController controller;
  const WebViewWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand();
}
