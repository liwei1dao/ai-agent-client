import 'dart:async';

import 'package:agents_server/agents_server.dart';
import 'package:flutter/foundation.dart';
import 'package:local_db/local_db.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/agent_config_builder.dart';
import '../../../core/services/locale_service.dart';

/// 悬浮窗对话所处阶段（驱动桌宠形象动效）。
enum OverlayAssistantPhase {
  /// 待机：没有会话。
  idle,

  /// 正在建立连接（createAgent → connectService → ready）。
  starting,

  /// 通话中·聆听用户（含 STT 识别中与轮次间歇）。
  listening,

  /// 通话中·AI 在想/说（LLM 生成、TTS 合成与播放）。
  speaking,

  /// 出错短暂提示，几秒后自动回 idle。
  error,
}

/// 启动前置条件不满足（未配置默认 agent / 无麦克风权限）。
/// UI 捕获后回退为拉起 app 让用户补齐。
class OverlayAssistantUnavailable implements Exception {
  const OverlayAssistantUnavailable(this.reason);

  /// 'no_mic_permission' | 'no_agent'
  final String reason;
}

/// 用户在连接中主动取消（区别于失败：安静回待机，不闪错误色）。
class _Cancelled implements Exception {
  const _Cancelled();
}

/// 悬浮窗「桌宠对话」会话控制器（跑在 overlay isolate，纯 Dart、无 Riverpod）。
///
/// 与主 app 的 AssistantChatController 同一套启动链路：createAgent →
/// connectService → 等 AgentReadyEvent → setInputMode('call')。区别：
/// - 配置自取：SharedPreferences（默认 agent/语言；进程级共享，读前 reload
///   防主 app 改完配置这边读到陈值）+ LocalDbBridge（agent/服务配置，走
///   native SQLite，跨 engine 天然共享）；
/// - sessionId 固定 [sessionId]，与主界面会话（agent.id）隔离；主 app 关闭
///   浮窗时也按此 id 防御性收尾（overlay engine 被销毁不会走 dispose）；
/// - 不收集对话文本，只产出驱动形象动效的 [phase]。
class OverlayAssistantSession extends ChangeNotifier {
  OverlayAssistantSession({AgentsServerBridge? bridge})
      : _bridge = bridge ?? AgentsServerBridge();

  /// 桌宠会话的固定 agent 实例 id。
  static const String sessionId = 'desktop_pet';

  final AgentsServerBridge _bridge;
  StreamSubscription<AgentEvent>? _sub;
  Completer<bool>? _ready;
  Timer? _errorReset;
  bool _cancelRequested = false;

  OverlayAssistantPhase _phase = OverlayAssistantPhase.idle;
  String? _lastError;

  OverlayAssistantPhase get phase => _phase;
  String? get lastError => _lastError;

  bool get _isActive =>
      _phase == OverlayAssistantPhase.listening ||
      _phase == OverlayAssistantPhase.speaking;

  /// 单击入口：待机/出错 → 开聊；连接中 → 取消；通话中 → 挂断。
  Future<void> toggle() async {
    switch (_phase) {
      case OverlayAssistantPhase.idle:
      case OverlayAssistantPhase.error:
        await start();
      case OverlayAssistantPhase.starting:
        // 取消正在进行的连接。标记位兜住 createAgent 尚未返回、_ready 还没
        // 建出来的窗口期；start() 在各个 await 之间检查它并安静收尾。
        _cancelRequested = true;
        _completeReady(false);
      case OverlayAssistantPhase.listening:
      case OverlayAssistantPhase.speaking:
        await stop();
    }
  }

  /// 启动桌宠通话。前置条件不满足抛 [OverlayAssistantUnavailable]。
  Future<void> start() async {
    if (_phase != OverlayAssistantPhase.idle &&
        _phase != OverlayAssistantPhase.error) {
      return;
    }
    _errorReset?.cancel();
    _lastError = null;
    _cancelRequested = false;
    _setPhase(OverlayAssistantPhase.starting);
    try {
      // 权限申请对话框需要 Activity，overlay isolate 弹不出来 → 没权限只能
      // 回退拉起 app 让主界面去申请。
      if (!await Permission.microphone.isGranted) {
        throw const OverlayAssistantUnavailable('no_mic_permission');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final agentId = prefs.getString('default_assistant_agent_id');
      final userLang = LocaleService.toCanonical(
          prefs.getString('default_assistant_user_language') ?? 'zh-CN');

      AgentDto? agent;
      if (agentId != null) {
        for (final a in await LocalDbBridge().getAllAgents()) {
          if (a.id == agentId && (a.type == 'chat' || a.type == 'sts-chat')) {
            agent = a;
            break;
          }
        }
      }
      if (agent == null) {
        throw const OverlayAssistantUnavailable('no_agent');
      }

      final services = await LocalDbBridge().getAllServiceConfigs();
      final cfg = AgentConfigBuilder.forChat(
        agent: agent,
        allServices: services,
        userLanguage: userLang,
        inputMode: 'call',
      ).build();

      // native ChatAgentSession 落库每轮 message 时，agentId 外键指向 agents
      // 表（onDelete CASCADE）。桌宠用固定 [sessionId] 作 agentId，必须先在库里
      // 放一条同 id 的占位记录，否则首条 message 插入即触发 FOREIGN KEY 约束
      // 失败、未捕获异常崩溃整个 app。configJson 仅 Dart UI 读取，给空对象即可；
      // 该 id 在 agentListProvider 中被过滤，不对用户可见。
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await LocalDbBridge().upsertAgent(AgentDto(
        id: sessionId,
        name: '桌面助理',
        type: agent.type,
        configJson: '{}',
        createdAt: nowMs,
        updatedAt: nowMs,
      ));

      _sub = _bridge.eventStream
          .where((e) => e.sessionId == sessionId)
          .listen(_onEvent);

      await _bridge.createAgent(
        agentId: sessionId,
        agentType: agent.type,
        inputMode: 'call',
        sttVendor: cfg['sttVendor'] as String?,
        ttsVendor: cfg['ttsVendor'] as String?,
        llmVendor: cfg['llmVendor'] as String?,
        stsVendor: cfg['stsVendor'] as String?,
        astVendor: cfg['astVendor'] as String?,
        translationVendor: cfg['translationVendor'] as String?,
        sttConfigJson: cfg['sttConfigJson'] as String?,
        ttsConfigJson: cfg['ttsConfigJson'] as String?,
        llmConfigJson: cfg['llmConfigJson'] as String?,
        stsConfigJson: cfg['stsConfigJson'] as String?,
        astConfigJson: cfg['astConfigJson'] as String?,
        translationConfigJson: cfg['translationConfigJson'] as String?,
        extraParams:
            (cfg['extraParams'] as Map?)?.cast<String, String>() ?? const {},
      );

      if (_cancelRequested) throw const _Cancelled();

      // connectService 后必派发恰好一次 AgentReadyEvent（同主界面链路）。
      _ready = Completer<bool>();
      await _bridge.connectService(sessionId);
      final ok = await _ready!.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (_cancelRequested) throw const _Cancelled();
      if (!ok) {
        throw Exception(_lastError ?? '连接超时');
      }

      await _bridge.setInputMode(sessionId, 'call');
      _setPhase(OverlayAssistantPhase.listening);
    } on OverlayAssistantUnavailable {
      await _teardown();
      _setPhase(OverlayAssistantPhase.idle);
      rethrow;
    } on _Cancelled {
      // 用户主动取消：安静收尾回待机，不闪错误。
      await _teardown();
      _setPhase(OverlayAssistantPhase.idle);
    } catch (e) {
      _lastError ??= e.toString().replaceFirst('Exception: ', '');
      await _teardown();
      _flashError();
    }
  }

  /// 挂断并释放 agent。
  Future<void> stop() async {
    await _teardown();
    _setPhase(OverlayAssistantPhase.idle);
  }

  Future<void> _teardown() async {
    // 逐个 best-effort 释放（与主界面 AssistantChatController 一致）。
    try {
      await _bridge.stopListening(sessionId);
    } catch (_) {}
    try {
      await _bridge.interrupt(sessionId);
    } catch (_) {}
    try {
      await _bridge.disconnectService(sessionId);
    } catch (_) {}
    try {
      await _bridge.stopAgent(sessionId);
    } catch (_) {}
    try {
      await _bridge.deleteAgent(sessionId);
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    _errorReset?.cancel();
    unawaited(_teardown());
    super.dispose();
  }

  // ─── 事件 → 阶段 ─────────────────────────────────────────────────────────

  void _onEvent(AgentEvent event) {
    switch (event) {
      case AgentReadyEvent(:final ready, :final errorCode, :final errorMessage):
        if (!ready) _lastError = errorMessage ?? errorCode ?? '连接失败';
        _completeReady(ready);

      case ServiceConnectionStateEvent(
          :final connectionState,
          :final errorMessage
        ):
        if (connectionState == ServiceConnectionState.error) {
          _lastError = errorMessage ?? '连接失败';
          _completeReady(false);
          if (_isActive) {
            unawaited(_teardown());
            _flashError();
          }
        } else if (connectionState == ServiceConnectionState.disconnected &&
            _isActive) {
          // 服务端断链：收尾回待机。
          unawaited(_teardown());
          _setPhase(OverlayAssistantPhase.idle);
        }

      case SessionStateEvent(:final state):
        if (!_isActive) break;
        switch (state) {
          case AgentSessionState.llm:
          case AgentSessionState.tts:
          case AgentSessionState.playing:
            _setPhase(OverlayAssistantPhase.speaking);
          case AgentSessionState.idle:
          case AgentSessionState.listening:
          case AgentSessionState.stt:
            _setPhase(OverlayAssistantPhase.listening);
          case AgentSessionState.error:
            // 单轮失败不挂断：闪一下错误色，回到聆听继续下一轮。
            break;
        }

      case AgentErrorEvent(:final errorCode, :final message):
        _lastError = '[$errorCode] $message';
        _completeReady(false);

      default:
        break;
    }
  }

  void _completeReady(bool ready) {
    final c = _ready;
    if (c != null && !c.isCompleted) c.complete(ready);
  }

  void _flashError() {
    _setPhase(OverlayAssistantPhase.error);
    _errorReset?.cancel();
    _errorReset = Timer(const Duration(milliseconds: 2600), () {
      if (_phase == OverlayAssistantPhase.error) {
        _setPhase(OverlayAssistantPhase.idle);
      }
    });
  }

  void _setPhase(OverlayAssistantPhase next) {
    if (_phase == next) return;
    _phase = next;
    notifyListeners();
  }
}
