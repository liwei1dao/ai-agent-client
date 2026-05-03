import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/log_service.dart';
import 'entity/base_entity.dart';

class AuthInterceptor extends Interceptor {
  final String _signKey = '@214%67g15q4*67m17#4l67!'; // 替换为实际的密钥

  bool _shouldSuppressErrorSnackbar(DioException err) {
    final path = err.requestOptions.path;
    return path == '/api/home/user_getinfo';
  }

  bool _shouldSuppressBusinessErrorSnackbar(RequestOptions options) {
    final path = options.path;
    return path == '/api/home/user_getinfo';
  }

  String _mapBadResponseMessage(DioException err) {
    final statusCode = err.response?.statusCode;
    final statusMessage = (err.response?.statusMessage ?? '').toLowerCase();

    if (statusCode == 401 || statusCode == 403) {
      return 'loginExpiredPleaseRelogin'.tr;
    }

    if (statusCode == 404 || statusMessage.contains('record not found')) {
      return 'requestedResourceNotFound'.tr;
    }

    if (statusCode != null && statusCode >= 500) {
      return 'serverTemporarilyUnavailable'.tr;
    }

    return 'unknownError'.tr;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 与 ai-agent-client 共用同一个 token 源，登录成功后由 AuthNotifier
    // 调 ApiClient.setToken 写入。源项目用的 GetStorage("logintoken")
    // 这里没人写，所以走 ApiClient.token。
    final token = ApiClient.instance.token;
    options.headers['Authorization'] = token;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    options.headers['Ts'] = timestamp;
    options.headers['Sign'] = _generateSign(timestamp);
    LogService.instance.talker.info(
        '[meet-api] → ${options.method} ${options.path} '
        'auth=${token.isEmpty ? "<empty>" : "<${token.length} chars>"} '
        'ts=$timestamp '
        'query=${_dump(options.queryParameters)} '
        'body=${_dump(options.data)}');
    handler.next(options);
  }

  String _dump(dynamic v) {
    if (v == null) return 'null';
    try {
      if (v is Map || v is List) {
        final s = jsonEncode(v);
        return s.length > 800 ? '${s.substring(0, 800)}…' : s;
      }
      final s = v.toString();
      return s.length > 800 ? '${s.substring(0, 800)}…' : s;
    } catch (_) {
      return v.toString();
    }
  }

  String _generateSign(String timestamp) {
    // 按照“MD5(私钥 + 时间戳)”生成签名，与 Go 端保持一致
    final signStr = 'ts=${timestamp}key=${_signKey}';
    print("signStr: $signStr");
    return md5.convert(utf8.encode(signStr)).toString();
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    BaseEntity entity = BaseEntity.fromJson(response.data);
    if (entity.code == 0) {
      response.data = entity.data ?? {};
      LogService.instance.talker.info(
          '[meet-api] ← ${response.requestOptions.path} ok '
          'data=${_dump(response.data)}');
      handler.resolve(response);
      return;
    }
    // 业务错误：日志 + 可选 snackbar，**必须** reject 让调用方 catch 到，
    // 否则像"积分不足""record not found"会被默默吞掉，UI 状态没法回滚。
    LogService.instance.talker.info(
        '[meet-api] ← ${response.requestOptions.path} biz_err '
        'code=${entity.code} msg=${entity.message}');
    final code = entity.code ?? -1;
    final rawMessage = entity.message ?? '';
    if (!_shouldSuppressBusinessErrorSnackbar(response.requestOptions)) {
      final lowerMessage = rawMessage.toLowerCase();
      final displayMessage = lowerMessage.contains('record not found')
          ? 'requestedResourceNotFound'.tr
          : (rawMessage.isNotEmpty ? rawMessage : 'unknownError'.tr);
      Get.snackbar(
        'error'.tr, // 错误
        displayMessage,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.withOpacity(0.1),
        colorText: Colors.red,
      );
    }
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: ApiException(code, rawMessage.isEmpty ? '业务错误' : rawMessage),
      ),
      true,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.cancel:
        {
          Get.snackbar(
            'error'.tr, // 错误
            'requestCancellation'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
      case DioExceptionType.connectionTimeout:
        {
          Get.snackbar(
            'error'.tr, // 错误
            'connectionTimeout'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
      case DioExceptionType.sendTimeout:
        {
          Get.snackbar(
            'error'.tr, // 错误
            'requestTimeout'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
      case DioExceptionType.receiveTimeout:
        {
          Get.snackbar(
            'error'.tr, // 错误
            'responseTimeout'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
      case DioExceptionType.badResponse:
        {
          if (_shouldSuppressErrorSnackbar(err)) {
            handler.next(err);
            return;
          }

          Get.snackbar(
            'error'.tr, // 错误
            _mapBadResponseMessage(err),
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
      default:
        {
          Get.snackbar(
            'error'.tr, // 错误
            err.message ?? 'unknownError'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: Colors.red.withOpacity(0.1),
            colorText: Colors.red,
          );
        }
    }
    handler.next(err);
  }
}
