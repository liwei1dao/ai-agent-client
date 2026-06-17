import 'dart:async';

import 'package:agents_server/agents_server.dart';
import 'package:flutter/foundation.dart';
import 'package:local_db/local_db.dart';

import '../../../core/services/agent_config_builder.dart';

/// AI 助理对话气泡（user / assistant）。
///
/// [streaming] 为 true 表示文本仍在产生中（用户 STT partial / 助理 LLM 流式），
/// UI 据此显示半透明斜体。
class AssistantBubble {
  AssistantBubble({
    required this.id,
    required this.isUser,
    required this.text,
    this.streaming = false,
  });

  final String id;
  final bool isUser;
  String text;
  bool streaming;
}

/// AI 助理「系统麦克风自麦」控制器。
///
/// 不再依赖 BLE / 设备端口：直接通过 [AgentsServerBridge] 跑一个 chat / sts-chat
/// agent，音频走系统麦克风（Android 上 `AudioRecord(VOICE_COMMUNICATION)` 会经
/// 经典蓝牙 HFP/SCO 自动路由到已连接的蓝牙耳机），TTS 走系统扬声器播放。
///
/// 交互为「连续免提通话」：[start] 后持续拾音，三段式 chat 在 `inputMode=='call'`
/// 下每轮 `STT→LLM→TTS` 完成会自动重新拾音；sts-chat 走端到端 `startAudio`。
class AssistantChatController extends ChangeNotifier {
  AssistantChatController({AgentsServerBridge? bridge})
      : _bridge = bridge ?? AgentsServerBridge();

  final AgentsServerBridge _bridge;

  StreamSubscription<AgentEvent>? _sub;
  String? _sessionId;
  Completer<bool>? _readyCompleter;
  int _seq = 0;

  bool _starting = false;
  bool _active = false;
  bool _passive = false;
  String? _lastError;
  final List<AssistantBubble> _bubbles = [];

  bool get isStarting => _starting;
  bool get isActive => _active;

  /// 是否处于「被动镜像」：会话由对端（桌宠悬浮助理）持有，本控制器只订阅事件流
  /// 同步聊天内容，不持有 agent。
  bool get isPassive => _passive;
  String? get lastError => _lastError;
  List<AssistantBubble> get bubbles => List.unmodifiable(_bubbles);

  /// 从本地库加载该 agent 的历史消息作为对话基底。
  ///
  /// 浮窗桌宠现在与本界面共用同一个 agent 会话（同一份消息历史），所以这里加载到
  /// 的内容也包含桌宠刚刚聊过的对话——这是「浮窗 ↔ 界面同步」的关键。界面打开时
  /// 与每次 [start] 前都会调用。
  Future<void> loadHistory(String agentId) async {
    try {
      final msgs = await LocalDbBridge().getMessages(agentId, limit: 100);
      _bubbles
        ..clear()
        // getMessages 按 createdAt DESC 返回，reversed 还原为时间正序。
        ..addAll(msgs.reversed
            .where((m) => m.content.trim().isNotEmpty)
            .map((m) => AssistantBubble(
                  id: m.id,
                  isUser: m.role == 'user',
                  text: m.content,
                  streaming: false,
                )));
      notifyListeners();
    } catch (_) {
      // 历史加载失败不阻塞对话启动。
    }
  }

  /// 进入「被动镜像」：对端（桌宠悬浮助理）持有会话时，本控制器订阅同一 agent 的
  /// 事件流，把 STT / LLM 消息实时映射到聊天面板——让「界面打开着、桌宠正在通话」
  /// 时聊天内容也实时同步，而不只是连接状态。
  ///
  /// 与 [start] 的根本区别：**不** createAgent、**不** stopAgent——会话归对端，本控制
  /// 器只是旁听者。两者跑在同一 native agent（sessionId = agent.id），事件经 native
  /// 多 engine fan-out 也会送到主 app 这侧，故订阅同一 sessionId 即可收到。
  Future<void> startPassive(String agentId) async {
    if (_active || _starting) return; // 自己（将）持有会话时无需镜像
    if (_passive && _sessionId == agentId) return; // 已在镜像同一会话
    await _sub?.cancel();
    _passive = true;
    _sessionId = agentId;
    await loadHistory(agentId);
    // loadHistory 是异步的，期间可能被 start()/stopPassive 抢断（_passive 置回
    // false）；若已不再处于本次镜像则放弃订阅，避免覆盖 start() 建立的订阅。
    if (!_passive || _sessionId != agentId) return;
    _sub = _bridge.eventStream
        .where((e) => e.sessionId == agentId)
        .listen(_handleEvent);
    notifyListeners();
  }

  /// 退出被动镜像（仅取消订阅，**绝不** stopAgent——会话是对端持有的）。已加载的
  /// 气泡保留在面板上。
  Future<void> stopPassive() async {
    if (!_passive) return;
    _passive = false;
    await _sub?.cancel();
    _sub = null;
    _sessionId = null;
    notifyListeners();
  }

  /// 启动一次 AI 助理通话。[agent] 必须是 chat / sts-chat 类型。
  Future<void> start({
    required AgentDto agent,
    required String userLanguage,
    required List<ServiceConfigDto> services,
  }) async {
    if (_active || _starting) return;
    // 若正处于被动镜像（对端会话），先退出：会话即将由本界面持有，旧镜像订阅必须
    // 取消以免对同一事件流重复订阅。只取消订阅，绝不动对端 agent。
    if (_passive) {
      _passive = false;
      await _sub?.cancel();
      _sub = null;
    }
    _starting = true;
    _lastError = null;
    notifyListeners();

    final sessionId = agent.id;
    _sessionId = sessionId;
    try {
      // 以持久化历史为基底（含浮窗桌宠刚聊的内容），再在其上追加本次实时消息。
      await loadHistory(sessionId);

      final cfg = AgentConfigBuilder.forChat(
        agent: agent,
        allServices: services,
        userLanguage: userLanguage,
        inputMode: 'call',
      ).build();

      _sub = _bridge.eventStream
          .where((e) => e.sessionId == sessionId)
          .listen(_handleEvent);

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

      // connectService 后必派发恰好一次 AgentReadyEvent：
      //   三段式 = 服务初始化完成；端到端 = WebSocket 链路 connected。
      _readyCompleter = Completer<bool>();
      await _bridge.connectService(sessionId);
      final ready = await _readyCompleter!.future
          .timeout(const Duration(seconds: 20), onTimeout: () => false);
      if (!ready) {
        throw Exception(_lastError ?? '连接超时');
      }

      // 切到 call 模式开始连续自麦：
      //   chat     → startContinuousListening（系统麦克风）
      //   sts-chat → stsService.startAudio（端到端自麦）
      await _bridge.setInputMode(sessionId, 'call');
      _active = true;
    } catch (e) {
      _lastError = e.toString().replaceFirst('Exception: ', '');
      await _teardown();
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  /// 挂断并释放 agent。
  Future<void> stop() async {
    await _teardown();
    notifyListeners();
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _teardown() async {
    final id = _sessionId;
    _active = false;
    if (id != null) {
      // 逐个 best-effort 释放；三段式 agent 对 disconnectService 可能是 no-op。
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
  }

  @override
  void dispose() {
    if (_passive) {
      // 被动镜像：会话归对端，只取消订阅；绝不 _teardown（它会 stopAgent，把桌宠
      // 正在用的 agent 杀掉）。
      _sub?.cancel();
    } else {
      // fire-and-forget 释放原生资源。
      unawaited(_teardown());
    }
    super.dispose();
  }

  // ─── 事件 → 气泡 ─────────────────────────────────────────────────────────

  void _handleEvent(AgentEvent event) {
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
        }

      case SttEvent(:final kind, :final text):
        _handleStt(kind, text);

      case LlmEvent(
          :final kind,
          :final textDelta,
          :final requestId,
          :final fullText
        ):
        _handleLlm(kind, textDelta, requestId, fullText);

      case AgentErrorEvent(:final errorCode, :final message):
        _lastError = '[$errorCode] $message';

      default:
        break;
    }
    notifyListeners();
  }

  void _completeReady(bool ready) {
    final c = _readyCompleter;
    if (c != null && !c.isCompleted) c.complete(ready);
  }

  void _handleStt(SttEventKind kind, String? text) {
    final t = text ?? '';
    if (t.isEmpty) return;
    if (kind == SttEventKind.partialResult) {
      final idx = _bubbles.lastIndexWhere((b) => b.isUser && b.streaming);
      if (idx != -1) {
        _bubbles[idx].text = t;
      } else {
        _bubbles.add(AssistantBubble(
            id: 'user_${_seq++}', isUser: true, text: t, streaming: true));
      }
    } else if (kind == SttEventKind.finalResult) {
      final idx = _bubbles.lastIndexWhere((b) => b.isUser && b.streaming);
      if (idx != -1) {
        _bubbles[idx]
          ..text = t
          ..streaming = false;
      } else {
        _bubbles.add(AssistantBubble(
            id: 'user_${_seq++}', isUser: true, text: t, streaming: false));
      }
    }
  }

  void _handleLlm(
      LlmEventKind kind, String? textDelta, String requestId, String? fullText) {
    final idx = _bubbles.indexWhere((b) => !b.isUser && b.id == requestId);
    // 三段式 / 端到端：每个 token delta 都以 firstToken 下发（idx==-1 时首帧新建，
    // 后续 append）。
    if (kind == LlmEventKind.firstToken && textDelta != null) {
      if (idx == -1) {
        _bubbles.add(AssistantBubble(
            id: requestId, isUser: false, text: textDelta, streaming: true));
      } else {
        _bubbles[idx].text += textDelta;
      }
    } else if (kind == LlmEventKind.done) {
      if (idx != -1) {
        if (_bubbles[idx].text.isEmpty && (fullText ?? '').isNotEmpty) {
          _bubbles[idx].text = fullText!;
        }
        _bubbles[idx].streaming = false;
      } else if ((fullText ?? '').isNotEmpty) {
        _bubbles.add(AssistantBubble(
            id: requestId, isUser: false, text: fullText!, streaming: false));
      }
    } else if (kind == LlmEventKind.error) {
      _lastError = '回复失败';
    }
  }
}
