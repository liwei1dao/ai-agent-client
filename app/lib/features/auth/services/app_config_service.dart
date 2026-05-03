import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/log_service.dart';

/// 服务端登录后下发的应用配置。结构与源项目 `UserGetAppConfigResp` 对齐 —
/// 这里只关心 `env`（含腾讯 COS 配置），其余字段按需取出 raw map。
class RemoteAppConfig {
  const RemoteAppConfig({
    required this.env,
    this.agents = const [],
    this.mcps = const {},
    this.products = const [],
  });

  final Map<String, String> env;
  final List<dynamic> agents;
  final Map<String, dynamic> mcps;
  final List<dynamic> products;

  /// COS 配置 — 缺一不可
  String get cosBucket => env['COS_BUCKET_NAME'] ?? '';
  String get cosRegion => env['COS_REGION'] ?? '';
  String get cosSecretId => env['COS_SECRET_ID'] ?? '';
  String get cosSecretKey => env['COS_SECRET_KEY'] ?? '';

  bool get hasCos =>
      cosBucket.isNotEmpty &&
      cosRegion.isNotEmpty &&
      cosSecretId.isNotEmpty &&
      cosSecretKey.isNotEmpty;

  factory RemoteAppConfig.fromJson(Map<String, dynamic> json) {
    final env = <String, String>{};
    final raw = json['env'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v != null) env[k.toString()] = v.toString();
      });
    }
    return RemoteAppConfig(
      env: env,
      agents: (json['agents'] as List?) ?? const [],
      mcps: (json['mcps'] as Map?)?.cast<String, dynamic>() ?? const {},
      products: (json['products'] as List?) ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'env': env,
        'agents': agents,
        'mcps': mcps,
        'products': products,
      };

  static const empty = RemoteAppConfig(env: {});
}

/// Loads & caches `RemoteAppConfig`. Mock 模式下返回空配置（不影响 UI 但
/// 录音 COS 上传会被跳过）。
class AppConfigService {
  AppConfigService();

  static const _cacheKey = 'auth.app_config.v1';

  RemoteAppConfig _current = RemoteAppConfig.empty;
  RemoteAppConfig get current => _current;

  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      _current = RemoteAppConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(_current.toJson()));
    } catch (_) {}
  }

  Future<void> clear() async {
    _current = RemoteAppConfig.empty;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
  }

  /// 拉取 `/api/home/user_getappconfig`。token 由 [ApiClient] 自动附带。
  Future<RemoteAppConfig> refresh(String token) async {
    ApiClient.instance.setToken(token);
    final dio = ApiClient.instance.maybeDio();
    if (dio == null) {
      // mock 模式：保留空配置即可，COS 自动跳过
      LogService.instance.talker
          .info('[appconfig] API_BASE_URL 未配置，跳过 refresh');
      return _current;
    }
    try {
      final res = await dio.post('/api/home/user_getappconfig');
      // ApiClient 拦截器已经拆掉 `data` 外层，res.data 直接就是 payload
      final root = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      _current = RemoteAppConfig.fromJson(root);
      await _persist();
      LogService.instance.talker.info('[appconfig] refreshed: '
          'env=${_current.env.length} keys, hasCos=${_current.hasCos} '
          'bucket=${_current.cosBucket} region=${_current.cosRegion}');
      return _current;
    } catch (e) {
      LogService.instance.talker.error('[appconfig] refresh failed: $e');
      rethrow;
    }
  }
}

final appConfigServiceProvider =
    Provider<AppConfigService>((_) => AppConfigService());
