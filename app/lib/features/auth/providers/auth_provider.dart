import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../../core/utils/upload_oss.dart';
import '../../../data/services/meeting/meeting_template_service.dart';
import '../../../data/services/meeting/meeting_user_scope.dart';
import '../models/user.dart';
import '../services/app_config_service.dart';
import '../services/auth_api.dart';
import '../services/auth_storage.dart';
import '../services/device_info_service.dart';

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
  });

  final AuthStatus status;
  final User? user;
  final String? error;

  bool get isAuthed => status == AuthStatus.authed && user != null;

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? error,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: error,
      );

  static const initializing = AuthState(status: AuthStatus.initializing);
}

enum AuthStatus { initializing, unauthed, authed }

final authApiProvider = Provider<AuthApi>((_) => AuthApi.create());
final authStorageProvider = Provider<AuthStorage>((_) => AuthStorage());

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(
    ref.watch(authApiProvider),
    ref.watch(authStorageProvider),
    ref.watch(appConfigServiceProvider),
  )..bootstrap(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api, this._storage, this._appConfig)
      : super(AuthState.initializing);

  final AuthApi _api;
  final AuthStorage _storage;
  final AppConfigService _appConfig;

  Future<void> bootstrap() async {
    // 初始化设备指纹（异步预热，登录时即用即拿）
    unawaited(DeviceInfoService.instance.ensureReady());
    // 加载缓存的 AppConfig（含 COS keys），无需等待网络
    unawaited(_appConfig.loadCached());

    final user = await _storage.read();
    if (user == null || user.token.isEmpty) {
      ApiClient.instance.clearToken();
      state = const AuthState(status: AuthStatus.unauthed);
      return;
    }

    // 关键：必须在任何接口调用前先把 token 挂到 ApiClient，
    // 否则 `_AuthInterceptor` 拿到的是空字符串，服务端会判 nologin。
    ApiClient.instance.setToken(user.token);
    // 切账号检测：如果上次落地的 uid 与本次不同就清本地会议缓存。
    await MeetingUserScope.onLogin(user.id);
    // 先用本地缓存进入已登录态，避免冷启动闪屏
    state = AuthState(status: AuthStatus.authed, user: user);

    // 后台用 token 拉一次最新用户信息；失败按 token 失效处理。
    unawaited(_refreshUserAndConfig(user));
  }

  Future<void> _refreshUserAndConfig(User cached) async {
    try {
      final fresh = await _api.getUserInfo();
      // getUserInfo 返回的 token 是空串，保留本地原 token
      final merged = User(
        id: fresh.id.isNotEmpty ? fresh.id : cached.id,
        token: cached.token,
        phone: fresh.phone ?? cached.phone,
        email: fresh.email ?? cached.email,
        name: (fresh.name ?? '').isNotEmpty ? fresh.name : cached.name,
        avatar: (fresh.avatar ?? '').isNotEmpty ? fresh.avatar : cached.avatar,
        countryCode: fresh.countryCode ?? cached.countryCode,
        loginType: fresh.loginType,
      );
      await _storage.write(merged);
      state = AuthState(status: AuthStatus.authed, user: merged);
    } catch (e) {
      // token 失效或网络异常：保留本地 cached 状态，等下次进入再判
      if (e is AuthException && e.code == 'server_error') {
        // 服务端明确拒绝（含 nologin）：清掉本地登录态
        await _storage.clear();
        await _appConfig.clear();
        ApiClient.instance.clearToken();
        state = const AuthState(status: AuthStatus.unauthed);
        return;
      }
    }
    // 用户信息刷新成功才继续刷 AppConfig
    unawaited(_refreshAppConfig(cached.token));
  }

  Future<void> _refreshAppConfig(String token) async {
    try {
      ApiClient.instance.setToken(token);
      await _appConfig.refresh(token);
    } catch (_) {}
    // 把腾讯云 COS 凭据 + 当前 uid 灌进 UploadOss，供会议录音上传使用。
    final cfg = _appConfig.current;
    final uid = state.user?.id ?? '';
    if (cfg.hasCos && uid.isNotEmpty) {
      UploadOss.configure(
        bucket: cfg.cosBucket,
        region: cfg.cosRegion,
        secretId: cfg.cosSecretId,
        secretKey: cfg.cosSecretKey,
        userId: uid,
      );
    }
    // AppConfig 刷新完顺手把会议模版拉一次（生成弹窗数据源）。
    unawaited(MeetingTemplateService.refresh());
  }

  Future<void> sendCode({
    required String contact,
    required String countryCode,
  }) async {
    final isEmail = countryCode.isEmpty;
    await _api.sendVerificationCode(
      addr: isEmail ? contact : '$countryCode$contact',
      vtype: isEmail ? 0 : 1,
    );
  }

  Future<bool> loginWithCode({
    required String contact,
    required String countryCode,
    required String code,
  }) async {
    try {
      final isEmail = countryCode.isEmpty;
      final user = await _api.signInWithCode(
        type: isEmail ? LoginType.email : LoginType.phone,
        contact: contact,
        countryCode: countryCode,
        code: code,
      );
      await _storage.write(user);
      ApiClient.instance.setToken(user.token);
      await MeetingUserScope.onLogin(user.id);
      state = AuthState(status: AuthStatus.authed, user: user);
      unawaited(_refreshAppConfig(user.token));
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
      return false;
    }
  }

  /// 第三方登录 — Google / Apple / Facebook。游客请改用 [loginAsGuest]。
  Future<bool> loginWithThirdParty({
    required LoginType type,
    required String idToken,
    String? email,
    String? name,
    String? avatar,
  }) async {
    try {
      final user = await _api.signInWithThirdParty(
        type: type,
        idToken: idToken,
        email: email,
        name: name,
        avatar: avatar,
      );
      await _storage.write(user);
      ApiClient.instance.setToken(user.token);
      await MeetingUserScope.onLogin(user.id);
      state = AuthState(status: AuthStatus.authed, user: user);
      unawaited(_refreshAppConfig(user.token));
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
      return false;
    }
  }

  Future<bool> loginAsGuest() async {
    try {
      final user = await _api.signInAsGuest();
      await _storage.write(user);
      ApiClient.instance.setToken(user.token);
      await MeetingUserScope.onLogin(user.id);
      state = AuthState(status: AuthStatus.authed, user: user);
      unawaited(_refreshAppConfig(user.token));
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(error: '登录失败：$e');
      return false;
    }
  }

  Future<void> logout() async {
    final token = state.user?.token;
    if (token != null) {
      try {
        await _api.logout(token);
      } catch (_) {}
    }
    await _storage.clear();
    await _appConfig.clear();
    await MeetingUserScope.onLogout();
    ApiClient.instance.clearToken();
    state = const AuthState(status: AuthStatus.unauthed);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith();
  }
}

