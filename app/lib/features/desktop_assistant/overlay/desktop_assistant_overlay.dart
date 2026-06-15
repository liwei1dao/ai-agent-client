import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' show RiveAnimation;

import '../desktop_assistant_avatars.dart';
import 'overlay_assistant_session.dart';

/// 桌面悬浮助理形象，跑在 `flutter_overlay_window` 的**独立 overlay isolate**。
///
/// 该 isolate 由独立 FlutterEngine 运行，当前形象由主 app 通过
/// `FlutterOverlayWindow.shareData(avatarKey)` 推送，用
/// [desktopAssistantAvatarByKey] 解析成 Lottie 资源。
///
/// 交互（桌宠语义，不再"一点就进 app"）：
/// - **单击**：开始 / 结束 AI 语音对话（[OverlayAssistantSession.toggle]，直接命令
///   原生前台服务跑对话，主 app 不需要在前台甚至不需要活着）；
///   未配置默认 agent / 无麦克风权限时回退为拉起 app 补配置；
/// - **长按**：拉起 app 进完整聊天界面（走 [_nativeChannel]，handler 由
///   MainActivity 注册到 cached overlay engine）。
///
/// 视觉是「桌宠」样式：角色裸露 + 脚下椭圆投影，按窗口尺寸等比布局。
/// 对话状态可视化（aura 光环跟随角色）：
/// - 待机：仅漂浮；连接中：光环快速脉动 + 漂浮加速 + 「正在连接」提示；
/// - 聆听：品牌紫光环缓慢呼吸；说话：光环增亮 + 双层波纹扩散；
/// - 出错：红色光环 + 错误提示条，2.6s 后自动回待机。
class DesktopAssistantOverlay extends StatefulWidget {
  const DesktopAssistantOverlay({super.key});

  @override
  State<DesktopAssistantOverlay> createState() =>
      _DesktopAssistantOverlayState();
}

class _DesktopAssistantOverlayState extends State<DesktopAssistantOverlay>
    with TickerProviderStateMixin {
  static const _nativeChannel =
      MethodChannel('desktop_assistant/overlay_native');
  static const _brand = Color(0xFF6C63FF);
  static const _danger = Color(0xFFEF4444);

  String _avatarKey = kDesktopAssistantAvatars.first.key;
  StreamSubscription? _sub;
  bool _pressed = false;
  late final OverlayAssistantSession _session = OverlayAssistantSession();

  /// 入场弹跳；切换形象时 forward(from: 0.55) 复用为一次小弹跳。
  late final AnimationController _entrance = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));
  late final Animation<double> _entranceScale =
      CurvedAnimation(parent: _entrance, curve: Curves.elasticOut);

  /// 待机循环相位：漂浮 / 投影 / 光环呼吸共用；周期随对话状态变化。
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600))
    ..repeat();

  /// 说话时的扩散波纹；只在 speaking 阶段运转，省电。
  late final AnimationController _ripple = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _entrance.forward();
    _session.addListener(_onSessionChanged);
    // 主 app 推送形象 key；收到即切换，并弹跳一下提示形象已换。
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && event.isNotEmpty && mounted) {
        final changed = event != _avatarKey;
        setState(() => _avatarKey = event);
        if (changed) _entrance.forward(from: 0.55);
      }
    });
    // 通知主 app overlay 已就绪 → 主 app 回推当前形象。
    FlutterOverlayWindow.shareData('ready');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _entrance.dispose();
    _idle.dispose();
    _ripple.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final phase = _session.phase;
    // 漂浮节奏跟随状态：越"兴奋"动得越快。repeat() 从当前值续跑，不会跳变。
    _idle.duration = Duration(
        milliseconds: switch (phase) {
      OverlayAssistantPhase.idle => 3600,
      OverlayAssistantPhase.starting => 1600,
      OverlayAssistantPhase.listening => 2600,
      OverlayAssistantPhase.speaking => 2000,
      OverlayAssistantPhase.error => 3000,
    });
    if (_idle.isAnimating) _idle.repeat();
    if (phase == OverlayAssistantPhase.speaking) {
      _ripple.repeat();
    } else {
      _ripple.stop();
      _ripple.reset();
    }
    setState(() {});
  }

  Future<void> _onTap() async {
    try {
      await _session.toggle();
    } on OverlayAssistantUnavailable {
      // 缺配置 / 缺权限：桌宠自己聊不了，拉起 app 让用户补齐。
      await _launchApp();
    }
  }

  Future<void> _launchApp() async {
    try {
      await _nativeChannel.invokeMethod('launchApp');
    } catch (_) {
      // overlay engine 上的 channel 尚未就绪时静默忽略。
    }
  }

  /// 状态提示条文案；null = 不显示。
  String? get _hint => switch (_session.phase) {
        OverlayAssistantPhase.starting => '正在连接…',
        OverlayAssistantPhase.error => _session.lastError ?? '出错了',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final avatar = desktopAssistantAvatarByKey(_avatarKey);
    final phase = _session.phase;
    final hint = _hint;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(builder: (context, constraints) {
          final s = math.min(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            // 整个窗口区域可交互（角色形状不规则，按轮廓命中太难点）。
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: _onTap,
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _launchApp();
            },
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_idle, _entranceScale, _ripple]),
              builder: (context, child) {
                // bobN 0→1→0：角色升到最高时投影最小、最淡。
                final wave = math.sin(_idle.value * 2 * math.pi);
                final bobN = 0.5 + 0.5 * wave;
                final lift = bobN * s * 0.04;
                final shadowW = s * 0.42 * (1.05 - 0.22 * bobN);
                final shadowH = shadowW * 0.22;
                // 角色几何中心距窗口底部的高度（光环/波纹的圆心）。
                final charCenter = s * 0.49 + lift;
                final auraD = s * 0.85;
                final fastPulse =
                    0.5 + 0.5 * math.sin(_idle.value * 4 * math.pi);
                final (Color auraColor, double auraOpacity) = switch (phase) {
                  OverlayAssistantPhase.starting => (
                      _brand,
                      0.18 + 0.14 * fastPulse
                    ),
                  OverlayAssistantPhase.listening => (
                      _brand,
                      0.20 + 0.10 * bobN
                    ),
                  OverlayAssistantPhase.speaking => (
                      _brand,
                      0.30 + 0.10 * bobN
                    ),
                  OverlayAssistantPhase.error => (_danger, 0.30),
                  OverlayAssistantPhase.idle => (_brand, 0),
                };
                return Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // 脚下椭圆投影：BoxShadow 软边，避免 ImageFilter 模糊开销。
                    Positioned(
                      bottom: s * 0.015,
                      child: Container(
                        width: shadowW,
                        height: shadowH,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(
                              Radius.elliptical(shadowW / 2, shadowH / 2)),
                          color: Color.fromRGBO(0, 0, 0, 0.20 - 0.09 * bobN),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Color.fromRGBO(0, 0, 0, 0.16 - 0.07 * bobN),
                              blurRadius: shadowH,
                              spreadRadius: shadowH * 0.2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 对话状态光环：羽化径向渐变贴在角色身后，跟随漂浮。
                    if (auraOpacity > 0)
                      Positioned(
                        bottom: charCenter - auraD / 2,
                        child: IgnorePointer(
                          child: Container(
                            width: auraD,
                            height: auraD,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  auraColor.withValues(alpha: auraOpacity),
                                  auraColor.withValues(alpha: 0),
                                ],
                                stops: const [0.35, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // 说话波纹：两道错相扩散的圆环。
                    if (phase == OverlayAssistantPhase.speaking)
                      for (final t in [
                        _ripple.value,
                        (_ripple.value + 0.5) % 1.0
                      ])
                        Positioned(
                          bottom: charCenter - s * (0.55 + 0.40 * t) / 2,
                          child: IgnorePointer(
                            child: Container(
                              width: s * (0.55 + 0.40 * t),
                              height: s * (0.55 + 0.40 * t),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _brand.withValues(
                                      alpha: (1 - t) * 0.45),
                                  width: 1 + 2.5 * (1 - t),
                                ),
                              ),
                            ),
                          ),
                        ),
                    // 角色本体：脚底锚点，漂浮 + 入场/按压缩放。
                    Positioned(
                      bottom: s * 0.05 + lift,
                      child: Transform.scale(
                        scale: _entranceScale.value,
                        alignment: Alignment.bottomCenter,
                        child: AnimatedScale(
                          scale: _pressed ? 0.9 : 1.0,
                          alignment: Alignment.bottomCenter,
                          duration: const Duration(milliseconds: 110),
                          curve: Curves.easeOut,
                          child: SizedBox(
                            width: s * 0.88,
                            height: s * 0.88,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    // 状态提示条（连接中 / 错误），常态不占视觉。
                    if (hint != null)
                      Positioned(
                        top: 0,
                        child: IgnorePointer(
                          child: Container(
                            constraints: BoxConstraints(maxWidth: s - 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: phase == OverlayAssistantPhase.error
                                  ? const Color(0xCCB91C1C)
                                  : const Color(0xB3000000),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              hint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  decoration: TextDecoration.none),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey(avatar.key),
                  child: avatar.isRive
                      ? RiveAnimation.asset(avatar.asset, fit: BoxFit.contain)
                      : Lottie.asset(
                          avatar.asset,
                          fit: BoxFit.contain,
                          repeat: true,
                          // 资源加载失败时给个可见兜底，避免空白。
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.smart_toy,
                              size: 64,
                              color: Color(0xFF6C5CE7)),
                        ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
