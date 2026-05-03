import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart' as env_cfg;
import 'log_service.dart';

String _summarizeAny(dynamic v) {
  if (v == null) return 'null';
  try {
    if (v is FormData) {
      final fields = v.fields.map((e) => '${e.key}=${e.value}').join(', ');
      final files = v.files.map((e) => '${e.key}=${e.value.filename}').join(', ');
      return 'FormData{fields:[$fields], files:[$files]}';
    }
    if (v is Map || v is List) {
      final s = const JsonEncoder().convert(v);
      return s.length > 600 ? '${s.substring(0, 600)}…' : s;
    }
    final s = v.toString();
    return s.length > 600 ? '${s.substring(0, 600)}…' : s;
  } catch (_) {
    final s = v.toString();
    return s.length > 600 ? '${s.substring(0, 600)}…' : s;
  }
}

/// 与服务端 [auth_interceptor.dart](
/// /Users/liwei/work/flutter/deepvoice_client_liwei/lib/data/services/network/auth_interceptor.dart)
/// 协议保持一致的统一 Dio 工厂。
///
/// **请求约定：**
/// - `Authorization`: 裸 token（没有 `Bearer ` 前缀）
/// - `Ts`: 当前毫秒时间戳
/// - `Sign`: `md5("ts=<ts>key=<signKey>")`
///
/// **响应约定（统一包装）：**
/// ```json
/// { "code": 0, "data": {...}, "message": "..." }
/// ```
/// `code == 0` 时把 `data` 解包后赋给 `response.data`，业务代码直接拿；非 0
/// 时把 `response.data = null` 并通过 [ApiException] 抛错。
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// 与源项目一致的签名 key（不暴露到 UI）。
  static const _signKey = '@214%67g15q4*67m17#4l67!';

  String _token = '';
  final bool _verboseLog = true;

  /// 暴露给 legacy `AuthInterceptor` 共用，避免出现两份 token 状态。
  String get token => _token;
  bool get hasToken => _token.isNotEmpty;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = '';
  }

  Dio? _dio;

  /// 当 `.env` 没配 `API_BASE_URL` 时返回 null（mock 模式）。
  Dio? maybeDio() {
    final base = env_cfg.AppConfig.instance.apiBaseUrl;
    if (base.isEmpty) return null;
    if (_dio != null && _dio!.options.baseUrl == base) return _dio;
    final d = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    d.interceptors.add(_AuthInterceptor(this));
    _dio = d;
    return d;
  }

  String _generateSign(String ts) =>
      md5.convert(utf8.encode('ts=${ts}key=$_signKey')).toString();

  void _log(String msg) {
    if (_verboseLog) LogService.instance.talker.info('[api] $msg');
  }
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._client);
  final ApiClient _client;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 与源项目 [auth_interceptor.onRequest](
    // /Users/liwei/work/flutter/deepvoice_client_liwei/lib/data/services/network/auth_interceptor.dart)
    // 1:1 镜像 —— 无条件写 Authorization（即使 token 为空），再加 Ts + Sign。
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    options.headers['Authorization'] = _client._token;
    options.headers['Ts'] = ts;
    options.headers['Sign'] = _client._generateSign(ts);
    _client._log('→ ${options.method} ${options.path} '
        'auth=${_client._token.isEmpty ? "<empty>" : "<${_client._token.length} chars>"} '
        'ts=$ts '
        'query=${_summarizeAny(options.queryParameters)} '
        'body=${_summarizeAny(options.data)}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final raw = response.data;
    if (raw is Map) {
      final code = raw['code'];
      final data = raw['data'];
      final msg = raw['message'] ?? raw['msg'];
      if (code is num && code == 0) {
        response.data = data ?? const {};
        _client._log('← ${response.requestOptions.path} ok '
            'data=${_summarize(response.data)}');
        return handler.next(response);
      }
      // 业务错误
      _client._log('← ${response.requestOptions.path} biz_err '
          'code=$code msg=$msg raw=${_summarize(raw)}');
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: ApiException(
            code is num ? code.toInt() : -1,
            (msg ?? '业务错误').toString(),
          ),
        ),
        true,
      );
      return;
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _client._log('× ${err.requestOptions.path} type=${err.type} '
        'status=${err.response?.statusCode} msg=${err.message}');
    handler.next(err);
  }

  String _summarize(dynamic v) {
    final s = v.toString();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }
}

class ApiException implements Exception {
  const ApiException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'ApiException($code, $message)';
}
