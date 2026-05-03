import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/api_client.dart';
import '../models/user.dart';
import 'device_info_service.dart';

/// 与后端 `/api/home/*` 协议对齐的统一登录入口。
///
/// 所有登录方式（邮箱 / 手机号 / Google / Apple / 游客）都打到
/// `POST /api/home/user_sgin`，由 `stype` 字段区分；验证码走
/// `POST /api/home/getCode`。
abstract class AuthApi {
  /// `addr` = 邮箱 或 国家码+手机号；`vtype` = 0(邮箱) / 1(手机)
  Future<void> sendVerificationCode({
    required String addr,
    required int vtype,
  });

  /// 邮箱验证码登录 (stype=0) 或 手机号验证码登录 (stype=1)。
  Future<User> signInWithCode({
    required LoginType type,
    required String contact,
    required String countryCode,
    required String code,
  });

  /// Google / Apple / Facebook 登录 — 第三方 token 必填。
  Future<User> signInWithThirdParty({
    required LoginType type,
    required String idToken,
    String? email,
    String? name,
    String? avatar,
  });

  /// 游客登录 (stype=6) — 不需要任何凭证，仅设备指纹。
  Future<User> signInAsGuest();

  /// 通过本地缓存的 token 直接拉取用户信息 (`/api/home/user_getinfo`)。
  /// token 由 [ApiClient] 拦截器自动写入 `Authorization` 头。
  /// 返回的 `User` 不含 token，调用方负责保留原 token。
  Future<User> getUserInfo();

  Future<void> logout(String token);

  static AuthApi create() {
    final base = AppConfig.instance.apiBaseUrl;
    return base.isEmpty ? MockAuthApi() : DioAuthApi(base);
  }
}

/// 本地 mock — `.env` 没配 `API_BASE_URL` 时使用。
class MockAuthApi implements AuthApi {
  final _rand = Random();

  @override
  Future<void> sendVerificationCode({
    required String addr,
    required int vtype,
  }) async {
    if (addr.trim().isEmpty) {
      throw const AuthException('contact_empty', '请输入手机号或邮箱');
    }
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Future<User> signInWithCode({
    required LoginType type,
    required String contact,
    required String countryCode,
    required String code,
  }) async {
    if (code.trim().length < 4) {
      throw const AuthException('code_invalid', '请输入正确的验证码');
    }
    await Future.delayed(const Duration(milliseconds: 500));
    return User(
      id: 'mock-${_rand.nextInt(1 << 30)}',
      token: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
      phone: type == LoginType.phone ? contact : null,
      email: type == LoginType.email ? contact : null,
      name: type == LoginType.email ? contact.split('@').first : '用户$contact',
      countryCode: countryCode,
      loginType: type,
    );
  }

  @override
  Future<User> signInWithThirdParty({
    required LoginType type,
    required String idToken,
    String? email,
    String? name,
    String? avatar,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return User(
      id: 'mock-${type.name}-${_rand.nextInt(1 << 30)}',
      token: 'mock-token-${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      name: name ??
          switch (type) {
            LoginType.apple => 'Apple 用户',
            LoginType.google => 'Google 用户',
            LoginType.facebook => 'Facebook 用户',
            _ => '用户',
          },
      avatar: avatar,
      loginType: type,
    );
  }

  @override
  Future<User> signInAsGuest() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return User(
      id: 'mock-guest-${_rand.nextInt(1 << 30)}',
      token: 'mock-guest-token-${DateTime.now().millisecondsSinceEpoch}',
      name: '游客',
      loginType: LoginType.guest,
    );
  }

  @override
  Future<User> getUserInfo() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return User(
      id: 'mock-cached',
      token: '',
      name: '本地用户',
      loginType: LoginType.guest,
    );
  }

  @override
  Future<void> logout(String token) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

/// 真后端实现 — 走共享的 [ApiClient]，自动签名 + 拆 `data`。
class DioAuthApi implements AuthApi {
  DioAuthApi(String baseUrl);

  Dio get _dio {
    final d = ApiClient.instance.maybeDio();
    if (d == null) {
      throw const AuthException('api_base_missing', 'API_BASE_URL 未配置');
    }
    return d;
  }

  @override
  Future<void> sendVerificationCode({
    required String addr,
    required int vtype,
  }) async {
    try {
      await _dio.post('/api/home/getCode', data: {
        'addr': addr,
        'vtype': vtype,
      });
    } on DioException catch (e) {
      throw _toAuthException(e);
    }
  }

  @override
  Future<User> signInWithCode({
    required LoginType type,
    required String contact,
    required String countryCode,
    required String code,
  }) async {
    await DeviceInfoService.instance.ensureReady();
    final isEmail = type == LoginType.email;
    return _signIn({
      'mail': isEmail ? contact : '',
      'phone': isEmail ? '' : '$countryCode$contact',
      'stype': type.code,
      'vcode': code,
      'ttoken': '',
      'name': '',
      'avatar': '',
    });
  }

  @override
  Future<User> signInWithThirdParty({
    required LoginType type,
    required String idToken,
    String? email,
    String? name,
    String? avatar,
  }) async {
    await DeviceInfoService.instance.ensureReady();
    return _signIn({
      'mail': email ?? '',
      'phone': '',
      'stype': type.code,
      'vcode': '',
      'ttoken': idToken,
      'name': name ?? '',
      'avatar': avatar ?? '',
    });
  }

  @override
  Future<User> signInAsGuest() async {
    await DeviceInfoService.instance.ensureReady();
    return _signIn({
      'mail': '',
      'phone': '',
      'stype': LoginType.guest.code,
      'vcode': '',
      'ttoken': '',
      'name': '',
      'avatar': '',
    });
  }

  Future<User> _signIn(Map<String, dynamic> partial) async {
    await DeviceInfoService.instance.ensureReady();
    final svc = DeviceInfoService.instance;
    // 服务端使用 protobuf：
    //   channel = UserChannel enum（uint32），传数字
    //   stype   = SginTyoe enum（uint32），partial 已是 int
    //   version = string，传应用版本字符串
    final body = {
      ...partial,
      'phonemodel': svc.deviceModel,
      'phonemac': svc.deviceId,
      'language': '',
      'channel': 0,
      'version': '1.0.0',
    };
    try {
      final res = await _dio.post('/api/home/user_sgin', data: body);
      // ApiClient 拦截器已拆 `data` 外层
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final token = (data['token'] ?? '').toString();
      if (token.isEmpty) {
        throw const AuthException('login_failed', '登录失败：未拿到 token');
      }
      // 用户信息可能在 `user` 子字段或顶层
      final u = (data['user'] is Map)
          ? Map<String, dynamic>.from(data['user'] as Map)
          : data;
      final stype = partial['stype'] as int;
      return User(
        id: (u['id'] ?? u['userid'] ?? u['uid'] ?? '').toString(),
        token: token,
        phone: (partial['phone'] as String).isEmpty
            ? (u['phone']?.toString())
            : partial['phone'] as String,
        email: (partial['mail'] as String).isEmpty
            ? (u['mail']?.toString() ?? u['email']?.toString())
            : partial['mail'] as String,
        name: (u['name'] ?? u['nickname'] ?? partial['name'] ?? '').toString(),
        avatar: (u['avatar'] ?? u['headimgurl'] ?? partial['avatar'] ?? '')
            .toString(),
        countryCode: u['country_code']?.toString(),
        loginType: LoginType.fromCode(stype),
      );
    } on DioException catch (e) {
      throw _toAuthException(e);
    }
  }

  @override
  Future<User> getUserInfo() async {
    try {
      final res = await _dio.post('/api/home/user_getinfo', data: {
        'channel': 0,
        'version': '1.0.0',
      });
      final root = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final u = (root['user'] is Map)
          ? Map<String, dynamic>.from(root['user'] as Map)
          : <String, dynamic>{};
      final stype = u['stype'] is num
          ? (u['stype'] as num).toInt()
          : (root['stype'] is num ? (root['stype'] as num).toInt() : null);
      return User(
        id: (u['uid'] ?? u['id'] ?? '').toString(),
        token: '',
        phone: (u['phone'] ?? '').toString().isEmpty
            ? null
            : u['phone'].toString(),
        email: (u['mail'] ?? u['email'] ?? '').toString().isEmpty
            ? null
            : (u['mail'] ?? u['email']).toString(),
        name: (u['name'] ?? '').toString(),
        avatar: (u['avatar'] ?? '').toString(),
        countryCode: u['country_code']?.toString(),
        loginType: stype != null ? LoginType.fromCode(stype) : LoginType.phone,
      );
    } on DioException catch (e) {
      throw _toAuthException(e);
    }
  }

  @override
  Future<void> logout(String token) async {
    try {
      await _dio.post('/api/home/user_logout');
    } catch (_) {
      // 登出失败不阻塞本地清理
    }
  }

  AuthException _toAuthException(DioException e) {
    final api = e.error;
    if (api is ApiException) {
      return AuthException('server_error', api.message);
    }
    return AuthException('network_error', e.message ?? '网络错误');
  }
}

class AuthException implements Exception {
  const AuthException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code, $message)';
}
