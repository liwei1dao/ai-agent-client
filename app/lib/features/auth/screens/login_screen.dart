import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/country.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_picker_sheet.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _contactCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  Country _country = kCountries[1]; // default 中国 +86
  bool _privacyAccepted = false;
  bool _sending = false;
  bool _loggingIn = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _contactCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _hintText => _country.code.isEmpty ? '邮箱' : '手机号码';
  bool get _isEmail => _country.code.isEmpty;

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown <= 1) {
        t.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _onSendCode() async {
    if (_sending || _countdown > 0) return;
    final contact = _contactCtrl.text.trim();
    if (contact.isEmpty) {
      _showSnack('请输入$_hintText');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(authProvider.notifier).sendCode(
            contact: contact,
            countryCode: _country.code,
          );
      if (!mounted) return;
      _showSnack('验证码已发送');
      _startCountdown();
    } catch (e) {
      _showSnack('发送失败：$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _onLogin() async {
    if (_loggingIn) return;
    if (!_privacyAccepted) {
      _showSnack('请先阅读并同意《用户协议》和《隐私政策》');
      return;
    }
    final contact = _contactCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (contact.isEmpty) {
      _showSnack('请输入$_hintText');
      return;
    }
    if (code.isEmpty) {
      _showSnack('请输入验证码');
      return;
    }
    setState(() => _loggingIn = true);
    final ok = await ref.read(authProvider.notifier).loginWithCode(
          contact: contact,
          countryCode: _country.code,
          code: code,
        );
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (ok) {
      context.go('/');
    } else {
      final err = ref.read(authProvider).error ?? '登录失败';
      _showSnack(err);
    }
  }

  Future<void> _onThirdParty(LoginType type) async {
    if (_loggingIn) return;
    if (!_privacyAccepted) {
      _showSnack('请先阅读并同意《用户协议》和《隐私政策》');
      return;
    }
    setState(() => _loggingIn = true);
    final notifier = ref.read(authProvider.notifier);
    final bool ok;
    if (type == LoginType.guest) {
      ok = await notifier.loginAsGuest();
    } else {
      // Apple / Google / Facebook：第三方 SDK 接入由后续迭代落地，
      // 当前先用占位 token 走通流程；mock 模式下会成功，真后端会校验失败。
      ok = await notifier.loginWithThirdParty(
        type: type,
        idToken: 'placeholder-token',
      );
    }
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (ok) {
      context.go('/');
    } else {
      final err = ref.read(authProvider).error ?? '登录失败';
      _showSnack(err);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickCountry() async {
    final c = await showCountryPicker(context);
    if (c != null) setState(() => _country = c);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 24),
                _AppLogo(),
                const SizedBox(height: 32),
                Text(
                  '欢迎使用',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.text1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '请使用手机号或邮箱登录',
                  style: TextStyle(fontSize: 13, color: colors.text2),
                ),
                const SizedBox(height: 24),
                _buildContactField(colors),
                const SizedBox(height: 12),
                _buildCodeField(colors),
                const SizedBox(height: 16),
                _buildLoginButton(),
                const SizedBox(height: 24),
                _buildDividerWithLabel(colors),
                const SizedBox(height: 16),
                _buildSocialButtons(colors),
                const SizedBox(height: 24),
                _buildPrivacy(colors),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactField(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 4),
                  Text(
                    _country.code.isEmpty ? 'Email' : _country.code,
                    style: TextStyle(fontSize: 14, color: colors.text1),
                  ),
                  Icon(Icons.arrow_drop_down, color: colors.text2, size: 20),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            color: colors.border,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          Expanded(
            child: TextField(
              controller: _contactCtrl,
              keyboardType: _isEmail
                  ? TextInputType.emailAddress
                  : TextInputType.phone,
              decoration: InputDecoration(
                hintText: _hintText,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              style: TextStyle(fontSize: 14, color: colors.text1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeField(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: colors.text2, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '验证码',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                counterText: '',
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              style: TextStyle(fontSize: 14, color: colors.text1),
            ),
          ),
          TextButton(
            onPressed: (_sending || _countdown > 0) ? null : _onSendCode,
            child: Text(
              _countdown > 0 ? '${_countdown}s 后重发' : '获取验证码',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _countdown > 0 ? colors.text2 : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _loggingIn ? null : _onLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _loggingIn
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text(
                '登录 / 注册',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildDividerWithLabel(AppColors colors) {
    return Row(
      children: [
        Expanded(child: Divider(color: colors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '或使用以下方式登录',
            style: TextStyle(fontSize: 12, color: colors.text2),
          ),
        ),
        Expanded(child: Divider(color: colors.border)),
      ],
    );
  }

  Widget _buildSocialButtons(AppColors colors) {
    final buttons = <_SocialButtonData>[];

    if (Platform.isAndroid) {
      buttons.add(_SocialButtonData(
          icon: Icons.g_mobiledata,
          color: const Color(0xFFDB4437),
          type: LoginType.google));
    }
    if (Platform.isIOS) {
      buttons.add(_SocialButtonData(
          icon: Icons.apple, color: colors.text1, type: LoginType.apple));
    }
    buttons.add(_SocialButtonData(
        icon: Icons.person_outline,
        color: colors.text2,
        type: LoginType.guest));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 24),
          _buildSocialButton(buttons[i], colors),
        ],
      ],
    );
  }

  Widget _buildSocialButton(_SocialButtonData data, AppColors colors) {
    return Material(
      color: colors.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _onThirdParty(data.type),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Icon(data.icon, color: data.color, size: 22),
        ),
      ),
    );
  }

  Widget _buildPrivacy(AppColors colors) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _privacyAccepted,
                onChanged: (v) => setState(() => _privacyAccepted = v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '登录/注册即表示同意',
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
            GestureDetector(
              onTap: () {},
              child: const Text(
                '《用户协议》',
                style: TextStyle(fontSize: 12, color: AppTheme.primary),
              ),
            ),
            Text('和', style: TextStyle(fontSize: 12, color: colors.text2)),
            GestureDetector(
              onTap: () {},
              child: const Text(
                '《隐私政策》',
                style: TextStyle(fontSize: 12, color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialButtonData {
  _SocialButtonData(
      {required this.icon, required this.color, required this.type});
  final IconData icon;
  final Color color;
  final LoginType type;
}

class _AppLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primaryDark],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.headset, color: Colors.white, size: 40),
    );
  }
}
