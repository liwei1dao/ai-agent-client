import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' show RiveAnimation;

import '../desktop_assistant_avatars.dart';
import 'overlay_assistant_session.dart';
import 'overlay_sync.dart';

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

  // 初值用「不显示」哨兵：主 app 回推真实 key（或显式隐藏）前先按隐藏渲染极简
  // 图标，避免短暂闪现默认角色。
  String _avatarKey = kHiddenAvatarKey;
  StreamSubscription? _sub;
  bool _pressed = false;
  late final OverlayAssistantSession _session = OverlayAssistantSession();

  /// 主 app（AssistantScreen）侧会话状态，经 shareData 同步而来。自己没在通话时，
  /// 桌宠据此镜像显示对方的「通话中 / 连接中」状态，并把单击改为「挂断对方」。
  OverlaySessionState _remoteState = OverlaySessionState.idle;

  /// 镜像对端（界面）会话时，对端最近一句用户话（经 shareData `msg:` 同步而来），
  /// 显示在头顶气泡。对端会话结束即清空。
  String _remoteUserText = '';

  /// 上次广播给主 app 的状态（去重，避免流式 notify 时反复打 channel）。
  OverlaySessionState _lastBroadcast = OverlaySessionState.idle;

  /// 自己会话的粗粒度状态（广播给主 app）。
  OverlaySessionState get _ownState => switch (_session.phase) {
        OverlayAssistantPhase.starting => OverlaySessionState.starting,
        OverlayAssistantPhase.listening ||
        OverlayAssistantPhase.speaking =>
          OverlaySessionState.active,
        OverlayAssistantPhase.idle ||
        OverlayAssistantPhase.error =>
          OverlaySessionState.idle,
      };

  /// 是否正由「自己」持有会话（自己非待机/出错）。
  bool get _ownsSession =>
      _session.phase != OverlayAssistantPhase.idle &&
      _session.phase != OverlayAssistantPhase.error;

  /// 用于驱动形象动效的有效阶段：自己持有会话时用自己的阶段，否则镜像对方状态。
  OverlayAssistantPhase get _effectivePhase {
    if (_ownsSession || _session.phase == OverlayAssistantPhase.error) {
      return _session.phase;
    }
    return switch (_remoteState) {
      OverlaySessionState.starting => OverlayAssistantPhase.starting,
      OverlaySessionState.active => OverlayAssistantPhase.listening,
      OverlaySessionState.idle => OverlayAssistantPhase.idle,
    };
  }

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
    // 自己持有会话时一条消息定稿 → 同步给界面对端（聊天内容双窗口同步）。
    _session.onFinalized = (role, text) {
      debugPrint('[SYNC] pet→screen msg role=$role len=${text.length}'); // 诊断
      try {
        FlutterOverlayWindow.shareData(OverlaySyncMsg.message(role, text));
      } catch (_) {}
    };
    // 主 app 推送的消息：会话同步协议（带前缀） / 形象 key（裸字符串）。
    _sub = FlutterOverlayWindow.overlayListener.listen(_onAppMessage);
    // 通知主 app overlay 已就绪 → 主 app 回推当前形象。
    FlutterOverlayWindow.shareData('ready');
    // 请求主 app 回播会话状态（界面可能正在通话，桌宠需镜像显示）。
    try {
      FlutterOverlayWindow.shareData(OverlaySyncMsg.syncRequest);
    } catch (_) {}
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

  /// 自己会话状态变化：刷新动效 + 把状态广播给主 app（保持两边「连接/挂断」同步）。
  void _onSessionChanged() {
    if (!mounted) return;
    _applyAnimations();
    setState(() {});
    _broadcastState();
  }

  /// 收到主 app 的 shareData 消息：先按会话同步协议判前缀，否则当作形象 key。
  void _onAppMessage(dynamic event) {
    if (event is! String || event.isEmpty || !mounted) return;
    debugPrint('[SYNC] pet←screen ' // 诊断，待删
        '${event.length > 60 ? '${event.substring(0, 60)}…' : event}');

    if (OverlaySyncMsg.isProtocol(event)) {
      final st = OverlaySyncMsg.parseState(event);
      if (st != null) {
        // 主 app 会话状态变化 → 镜像显示。
        if (_remoteState != st) {
          setState(() {
            _remoteState = st;
            // 界面会话结束 → 清掉镜像显示的用户话。
            if (st == OverlaySessionState.idle) _remoteUserText = '';
          });
          _applyAnimations();
        }
        return;
      }
      final msg = OverlaySyncMsg.parseMessage(event);
      if (msg != null) {
        // 界面（对端）持有会话时把定稿消息同步过来：桌宠只在头顶展示用户话（遵循
        // 「桌宠只显示用户说的话」），AI 回复仅由说话图标体现、不展示文字。
        if (!_ownsSession && msg.role == 'user') {
          setState(() => _remoteUserText = msg.text);
        }
        return;
      }
      if (event == OverlaySyncMsg.hangup) {
        // 主 app 要求桌宠挂断自己持有的会话。
        if (_ownsSession || _session.phase == OverlayAssistantPhase.starting) {
          _session.stop();
        }
      } else if (event == OverlaySyncMsg.syncRequest) {
        // 主 app（刚打开界面）请求当前状态 → 立即强制回播。
        _broadcastState(force: true);
      }
      return;
    }

    // 形象 key（裸字符串）。
    final changed = event != _avatarKey;
    setState(() => _avatarKey = event);
    if (changed) _entrance.forward(from: 0.55);
  }

  /// 把自己的会话状态广播给主 app（默认仅在变化时发；[force] 用于响应 sync 请求）。
  void _broadcastState({bool force = false}) {
    final s = _ownState;
    if (!force && s == _lastBroadcast) return;
    _lastBroadcast = s;
    debugPrint('[SYNC] pet→screen ${OverlaySyncMsg.state(s)}'); // 诊断，待删
    try {
      FlutterOverlayWindow.shareData(OverlaySyncMsg.state(s));
    } catch (_) {}
  }

  /// 漂浮/波纹动效跟随**有效阶段**（自己的或镜像对方的）。
  void _applyAnimations() {
    final phase = _effectivePhase;
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
  }

  Future<void> _onTap() async {
    // 对方（主界面）持有会话、自己空闲 → 单击 = 挂断对方（乐观清掉镜像状态）。
    if (!_ownsSession &&
        _session.phase != OverlayAssistantPhase.starting &&
        _remoteState != OverlaySessionState.idle) {
      try {
        FlutterOverlayWindow.shareData(OverlaySyncMsg.hangup);
      } catch (_) {}
      setState(() => _remoteState = OverlaySessionState.idle);
      _applyAnimations();
      return;
    }
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

  /// 头顶气泡内容：状态符号 + 文案（text 为 null = 只显示图标）。整体 null = 不显示。
  ///
  /// 需求：桌宠**只显示用户说的话**；AI 说话时只显示一个说话图标、不显示回复文字。
  /// - 连接中：「正在连接…」；
  /// - 聆听（自己通话）：麦克风符号 + 实时识别文本（无文本时「聆听中…」，明确告知已连上）；
  /// - 聆听（镜像主界面通话）：麦克风符号 +「通话中…」（拿不到主界面逐字文本）；
  /// - 说话：仅说话图标，不显示 AI 文字；
  /// - 出错：红色错误提示。
  ({String? text, IconData? icon, bool danger, bool italic})? get _head {
    switch (_effectivePhase) {
      case OverlayAssistantPhase.starting:
        return (text: '正在连接…', icon: null, danger: false, italic: true);
      case OverlayAssistantPhase.error:
        return (
          text: _session.lastError ?? '出错了',
          icon: Icons.error_outline,
          danger: true,
          italic: false,
        );
      case OverlayAssistantPhase.listening:
        if (_ownsSession) {
          final u = _session.userText;
          return (
            text: u.isEmpty ? '聆听中…' : u,
            icon: Icons.mic,
            danger: false,
            italic: u.isEmpty,
          );
        }
        // 镜像界面会话：显示界面同步来的用户话（拿不到则「通话中…」）。
        final r = _remoteUserText.trim();
        return (
          text: r.isEmpty ? '通话中…' : r,
          icon: Icons.mic,
          danger: false,
          italic: r.isEmpty,
        );
      case OverlayAssistantPhase.speaking:
        return (text: null, icon: Icons.graphic_eq, danger: false, italic: false);
      case OverlayAssistantPhase.idle:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 当前 agent 关闭了「显示虚拟形象」（或无可用 agent）→ 不渲染角色，退回极简
    // 图标；其余手势 / 状态光环 / 头顶气泡照常。
    final hidden = _avatarKey == kHiddenAvatarKey;
    final avatar = desktopAssistantAvatarByKey(_avatarKey);
    final phase = _effectivePhase;
    final head = _head;
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
                    // 头顶气泡：状态符号 + 用户识别文本（说话时仅图标）。待机不显示。
                    if (head != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Builder(builder: (_) {
                              final hasText =
                                  head.text != null && head.text!.isNotEmpty;
                              return Container(
                                constraints: BoxConstraints(maxWidth: s - 8),
                                padding: hasText
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6)
                                    : const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: head.danger
                                      ? const Color(0xD6B91C1C)
                                      : const Color(0xD61A1A1A),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (head.icon != null) ...[
                                      Icon(
                                        head.icon,
                                        size: hasText ? 13 : 18,
                                        color: head.danger
                                            ? Colors.white
                                            : const Color(0xFFB7B1FF),
                                      ),
                                      if (hasText) const SizedBox(width: 5),
                                    ],
                                    if (hasText)
                                      Flexible(
                                        child: Text(
                                          head.text!,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            height: 1.25,
                                            fontStyle: head.italic
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
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
                child: hidden
                    // 「不显示形象」：极简圆形图标，仍可单击发起对话 / 长按进 app。
                    ? KeyedSubtree(
                        key: const ValueKey(kHiddenAvatarKey),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _brand.withValues(alpha: 0.14),
                              border: Border.all(
                                  color: _brand.withValues(alpha: 0.55),
                                  width: 2),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Icon(Icons.smart_toy,
                                    size: 48, color: _brand),
                              ),
                            ),
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: ValueKey(avatar.key),
                        child: avatar.isRive
                            ? RiveAnimation.asset(avatar.asset,
                                fit: BoxFit.contain)
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
