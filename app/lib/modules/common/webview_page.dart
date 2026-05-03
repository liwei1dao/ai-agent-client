import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:get/get.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class WebViewPage extends StatelessWidget {
  final String url;
  final String title;

  const WebViewPage({Key? key, required this.url, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDarkMode ? Colors.white : Colors.black,
            size: 20.sp,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17.sp,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: WebViewWidget(
          controller: controller,
        ),
      ),
    );
  }
}
