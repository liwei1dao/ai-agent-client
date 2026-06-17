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
/// - sessionId **复用默认 agent 的真实 id**（不再用独立的 desktop_pet），所以浮窗
///   与主界面 AssistantScreen 是**同一段对话、同一份消息历史**：native 把每轮消息
///   落库到该 agent，AssistantScreen 打开时加载历史即可看到桌宠刚聊的内容；
/// - 除了驱动形象动效的 [phase]，还产出头顶展示用的识别文本 [userText] 与
///   AI 回复 [aiText]。
class OverlayAssistantSession extends ChangeNotifier {
  OverlayAssistantSession({AgentsServerBridge? bridge})
      : _bridge = bridge ?? AgentsServerBridge();

  final AgentsServerBridge _bridge;
  StreamSubscription<AgentEvent>? _sub;
  Completer<bool>? _ready;
  Timer? _errorReset;
  bool _cancelRequested = false;

  /// 本次会话使用的 agent id（= 默认 agent 的真实 id）；start() 时确定。
  String? _sessionId;

  OverlayAssistantPhase _phase = OverlayAssistantPhase.idle;
  String? _lastError;

  // 头顶展示用的对话文本。用户识别文本拆成「已定稿(committed) + 当前句(current)」
  // 两段（遵循 STT §3.1 覆盖/累加语义）；AI 回复按 requestId 累积。
  String _sttCommitted = '';
  String _sttCurrent = '';
  String _aiText = '';
  String _aiRequestId = '';

  OverlayAssistantPhase get phase => _phase;
  String? get lastError => _lastError;

  /// 用户最新识别文本（头顶气泡展示）。
  String get userText => (_sttCommitted + _sttCurrent).trim();

  /// AI 最新回复文本（头顶气泡展示）。
  String get aiText => _aiText.trim();

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
    _resetTranscript();
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

      // 复用默认 agent 的真实 id：浮窗与主界面 AssistantScreen 是同一段会话、同一份
      // 消息历史。native 落库每轮 message 的 agentId 外键指向 agents 表，该 agent
      // 已在库（用户创建过、上面也校验过存在），外键天然满足——无需占位记录，也
      // 不会污染用户可见列表。
      final sid = agent.id;
      _sessionId = sid;

      _sub = _bridge.eventStream
          .where((e) => e.sessionId == sid)
          .listen(_onEvent);

      await _bridge.createAgent(
        agentId: sid,
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
      await _bridge.connectService(sid);
      final ok = await _ready!.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (_cancelRequested) throw const _Cancelled();
      if (!ok) {
        throw Exception(_lastError ?? '连接超时');
      }

      await _bridge.setInputMode(sid, 'call');
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
    final id = _sessionId;
    if (id != null) {
      // 逐个 best-effort 释放（与主界面 AssistantChatController 一致）。
      try {
        await _bridge.stopListening(id);
      } catch (_) {}
      try {
        await _bridge.interrupt(id);
      } catch (_) {}
      try {
        await _bridge.disconnectService(id);
      } catch (_) {}
      try {
        await _bridge.stopAgent(id);
      } catch (_) {}
      try {
        await _bridge.deleteAgent(id);
      } catch (_) {}
    }
    await _sub?.cancel();
    _sub = null;
    _sessionId = null;
    _resetTranscript();
  }

  void _resetTranscript() {
    _sttCommitted = '';
    _sttCurrent = '';
    _aiText = '';
    _aiRequestId = '';
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

      case SttEvent(:final kind, :final text):
        _handleStt(kind, text);

      case LlmEvent(:final kind, :final textDelta, :final requestId, :final fullText):
        _handleLlm(kind, textDelta, requestId, fullText);

      case AgentErrorEvent(:final errorCode, :final message):
        _lastError = '[$errorCode] $message';
        _completeReady(false);

      default:
        break;
    }
  }

  /// 识别文本 → 头顶气泡。partial 覆盖当前句、final 累加（STT §3.1）；当上一轮
  /// AI 已回复后收到新的识别文本，视作新一轮，先清掉上轮文本。
  void _handleStt(SttEventKind kind, String? text) {
    if (kind != SttEventKind.partialResult &&
        kind != SttEventKind.finalResult) {
      return;
    }
    final t = text ?? '';
    if (t.isEmpty) return;
    if (_aiText.isNotEmpty) {
      _sttCommitted = '';
      _sttCurrent = '';
      _aiText = '';
      _aiRequestId = '';
    }
    if (kind == SttEventKind.partialResult) {
      _sttCurrent = t;
    } else {
      _sttCommitted += t;
      _sttCurrent = '';
    }
    notifyListeners();
  }

  /// AI 回复文本 → 头顶气泡。按 requestId 区分轮次：新轮次重置，同轮 append。
  void _handleLlm(
      LlmEventKind kind, String? textDelta, String requestId, String? fullText) {
    if (kind == LlmEventKind.firstToken && textDelta != null) {
      if (requestId != _aiRequestId) {
        _aiRequestId = requestId;
        _aiText = textDelta;
      } else {
        _aiText += textDelta;
      }
      notifyListeners();
    } else if (kind == LlmEventKind.done) {
      if (_aiText.isEmpty && (fullText ?? '').isNotEmpty) {
        _aiText = fullText!;
        notifyListeners();
      }
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
