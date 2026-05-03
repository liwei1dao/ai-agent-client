import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get/get.dart' hide Response, FormData;

import '../../../core/config/app_config.dart' as env_cfg;
import '../../../core/utils/logger.dart';
import '../../models/channel_app_model.dart';
import 'auth_interceptor.dart';
import 'nw_method.dart';

// Stub: replaces VersionUpdateService when not provided.
class VersionUpdateService extends GetxService {
  static VersionUpdateService get to => Get.find();
  UserChannel get cachedChannel {
    if (Platform.isIOS) return UserChannel.GLOBAL_APPLE;
    final channelName = dotenv.env['Channel'] ?? 'OFFICIAL';
    return UserChannel.fromName(channelName);
  }
}

class DioManager {
  static final DioManager _shared = DioManager._internal();
  factory DioManager() => _shared;

  late Dio dio;

  // 获取当前渠道信息，优先从版本服务获取，降级到平台判断和.env
  UserChannel get _currentChannel {
    try {
      if (Get.isRegistered<VersionUpdateService>()) {
        // print("lxm---${VersionUpdateService.to.cachedChannel}");
        return VersionUpdateService.to.cachedChannel;
      }
    } catch (_) {}
    // 版本服务未就绪时，根据平台判断
    if (Platform.isIOS) {
      return UserChannel.GLOBAL_APPLE;
    }
    final channelName = dotenv.env['Channel'] ?? 'OFFICIAL';
    return UserChannel.fromName(channelName);
  }

  // 根据地区获取服务器URL
  // 优先用 ai-agent-client 的统一配置 `API_BASE_URL`（与 ApiClient 一致），
  // 缺省时再回退源项目的 SERVER_URL / HW_SERVER_URL 旧逻辑。
  String get baseUrl {
    final unified = env_cfg.AppConfig.instance.apiBaseUrl;
    if (unified.isNotEmpty) return unified;
    final countryCode = Get.deviceLocale?.countryCode?.toUpperCase();
    final isChinaMainland = countryCode == 'CN';
    final channel = _currentChannel;
    if (!isChinaMainland || channel == UserChannel.GLOBAL_GOOGLE) {
      return dotenv.env['HW_SERVER_URL'] ?? '';
    } else {
      return dotenv.env['SERVER_URL'] ?? '';
    }
  }

  DioManager._internal() {
    BaseOptions options = BaseOptions(
      baseUrl: baseUrl,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    );

    dio = Dio(options);

    // 日志拦截器必须在 AuthInterceptor 前面，
    // 否则 AuthInterceptor 的 handler.resolve() 会跳过后续拦截器
    dio.interceptors.add(_ApiLogInterceptor());
    dio.interceptors.add(AuthInterceptor());
  }

  // 请求，返回参数为 T
  // method：请求方法，NWMethod.POST等
  // path：请求地址
  // params：请求参数
  Future request<T>(
    NWMethod method,
    String path, {
    Object? params,
    Map<String, dynamic>? queryParameters,
  }) async {
    // baseUrl 在 _internal() 构造时取一次，但那时 dotenv / AppConfig 可能还没就绪。
    // 每次请求前重新对齐当前 base，确保配置后生效。
    final current = baseUrl;
    if (current.isNotEmpty && dio.options.baseUrl != current) {
      dio.options.baseUrl = current;
    }
    Response response = await dio.request(
      path,
      data: params,
      queryParameters: queryParameters,
      options: Options(method: nwMethodValues[method]),
    );
    return response.data;
  }
}

/// API 请求/响应日志拦截器，写入文件日志
/// 必须放在 AuthInterceptor 之前，才能完整记录原始响应
class _ApiLogInterceptor extends Interceptor {
  static const String _tag = 'API';

  String _formatBody(dynamic data) {
    if (data == null) return 'null';
    try {
      if (data is FormData) {
        final fields = data.fields.map((e) => '${e.key}=${e.value}').join(', ');
        final files = data.files.map((e) => '${e.key}=${e.value.filename}').join(', ');
        return 'FormData{fields: [$fields], files: [$files]}';
      }
      if (data is Map || data is List) {
        return const JsonEncoder().convert(data);
      }
      return data.toString();
    } catch (_) {
      return data.toString();
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method;
    final path = options.path;
    final buf = StringBuffer();
    buf.writeln('>>> $method $path');
    if (options.queryParameters.isNotEmpty) {
      buf.writeln('    Query: ${_formatBody(options.queryParameters)}');
    }
    if (options.data != null) {
      buf.writeln('    Body: ${_formatBody(options.data)}');
    }
    Logger.i(_tag, buf.toString().trimRight());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final method = response.requestOptions.method;
    final path = response.requestOptions.path;
    final statusCode = response.statusCode;
    final buf = StringBuffer();
    buf.writeln('<<< $method $path [$statusCode]');
    buf.writeln('    Response: ${_formatBody(response.data)}');
    Logger.i(_tag, buf.toString().trimRight());
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final method = err.requestOptions.method;
    final path = err.requestOptions.path;
    final statusCode = err.response?.statusCode ?? 'N/A';
    final buf = StringBuffer();
    buf.writeln('<<< $method $path [$statusCode] ${err.type}: ${err.message}');
    if (err.response?.data != null) {
      buf.writeln('    Error Body: ${_formatBody(err.response?.data)}');
    }
    Logger.e(_tag, buf.toString().trimRight());
    handler.next(err);
  }
}
