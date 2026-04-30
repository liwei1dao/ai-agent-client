import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agents_server/agents_server.dart';
import 'package:local_db/local_db.dart';
import '../../../core/services/locale_service.dart';
// ─── State ────────────────────────────────────────────────────────────────────

const _sentinel = Object();

class AgentMessage {
  AgentMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
    this.translatedContent,
    this.detectedLang,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final String role;
  String content;
  String status; // pending | streaming | done | cancelled | error
  String? translatedContent; // 翻译文本（AST翻译模式：原文在content，译文在此）
  String? detectedLang;      // 检测到的源语言代码（用于翻译模式对齐）
  final DateTime createdAt;

  /// 是否为翻译配对消息（同时包含原文和译文）
  bool get isTranslationPair => translatedContent != null;
}

class AgentScreenState {
  const AgentScreenState({
    this.agentName = '',
    this.agentType = 'chat',
    this.sessionId = '',
    this.sessionState = AgentSessionState.idle,
    this.connectionState = ServiceConnectionState.disconnected,
    this.inputMode = 'text',
    this.messages = const [],
    this.sttPartial = '',
    this.recordingMsgId,
    this.pendingVoiceText = '',
    this.llmServiceName = '',
    this.sttServiceName = '',
    this.ttsServiceName = '',
    this.srcLang = 'zh-CN',
    this.dstLang = 'en-US',
    this.srcLangs = const ['zh-CN', 'en-US'],
    this.dstLangs = const ['en-US'],
    this.bidirectional = false,
    this.translateDirection = 'src_to_dst', // 'src_to_dst' | 'dst_to_src'
    this.sttSupportsLanguageDetection = false,
    this.logs = const [],
  });

  final String agentName;
  final String agentType; // 'chat' | 'translate' | 'sts' | 'ast'
  final String sessionId;
  final AgentSessionState sessionState;
  final ServiceConnectionState connectionState; // 端到端连接状态
  final String inputMode;
  final List<AgentMessage> messages;
  final String sttPartial;
  final String? recordingMsgId; // 录音中的临时气泡 id
  final String pendingVoiceText; // 松开后要发送的最终识别文本
  final String llmServiceName;
  final String sttServiceName;
  final String ttsServiceName;
  final String srcLang;  // 当前激活的源语言
  final String dstLang;  // 当前激活的目标语言
  final List<String> srcLangs; // Agent 配置支持的源语言列表
  final List<String> dstLangs; // Agent 配置支持的目标语言列表
  final bool bidirectional;    // 翻译 agent 互译开关（仅 STT 支持语言识别时可用）
  final String translateDirection; // 文本输入方向：src_to_dst | dst_to_src
  final bool sttSupportsLanguageDetection; // 当前 STT 厂商是否支持语言检测
  final List<String> logs;     // 运行日志（启动、连接、事件、错误）

  /// 是否为端到端模式（STS 聊天 / AST 翻译）
  bool get isEndToEnd => agentType == 'sts-chat' || agentType == 'ast-translate';

  /// 是否为翻译类 Agent（AST 翻译 / translate）
  bool get isTranslateMode => agentType == 'ast-translate' || agentType == 'translate';

  AgentScreenState copyWith({
    String? agentName,
    String? agentType,
    String? sessionId,
    AgentSessionState? sessionState,
    ServiceConnectionState? connectionState,
    String? inputMode,
    List<AgentMessage>? messages,
    String? sttPartial,
    Object? recordingMsgId = _sentinel,
    String? pendingVoiceText,
    String? llmServiceName,
    String? sttServiceName,
    String? ttsServiceName,
    String? srcLang,
    String? dstLang,
    List<String>? srcLangs,
    List<String>? dstLangs,
    bool? bidirectional,
    String? translateDirection,
    bool? sttSupportsLanguageDetection,
    List<String>? logs,
  }) =>
      AgentScreenState(
        agentName: agentName ?? this.agentName,
        agentType: agentType ?? this.agentType,
        sessionId: sessionId ?? this.sessionId,
        sessionState: sessionState ?? this.sessionState,
        connectionState: connectionState ?? this.connectionState,
        inputMode: inputMode ?? this.inputMode,
        messages: messages ?? this.messages,
        sttPartial: sttPartial ?? this.sttPartial,
        recordingMsgId: recordingMsgId == _sentinel
            ? this.recordingMsgId
            : recordingMsgId as String?,
        pendingVoiceText: pendingVoiceText ?? this.pendingVoiceText,
        llmServiceName: llmServiceName ?? this.llmServiceName,
        sttServiceName: sttServiceName ?? this.sttServiceName,
        ttsServiceName: ttsServiceName ?? this.ttsServiceName,
        srcLang: srcLang ?? this.srcLang,
        dstLang: dstLang ?? this.dstLang,
        srcLangs: srcLangs ?? this.srcLangs,
        dstLangs: dstLangs ?? this.dstLangs,
        bidirectional: bidirectional ?? this.bidirectional,
        translateDirection: translateDirection ?? this.translateDirection,
        sttSupportsLanguageDetection:
            sttSupportsLanguageDetection ?? this.sttSupportsLanguageDetection,
        logs: logs ?? this.logs,
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final agentScreenProvider =
    StateNotifierProvider.autoDispose
        .family<AgentScreenNotifier, AgentScreenState, String>(
  (ref, agentId) => AgentScreenNotifier(agentId),
);

class AgentScreenNotifier extends StateNotifier<AgentScreenState> {
  AgentScreenNotifier(this._agentId) : super(const AgentScreenState());

  final String _agentId;
  final _bridge = AgentsServerBridge();
  final _db = LocalDbBridge();
  StreamSubscription<AgentEvent>? _eventSub;
  bool _voiceCancelled = false; // 上滑取消标志

  /// 缓存 createAgent 入参（除 bidirectional 相关字段），切换互译开关时复用。
  Map<String, Object?>? _createAgentArgs;
  /// 缓存 STT serviceId（互译切换时重新构造 sttConfigJson）。
  String? _cachedSttId;

  /// Append a timestamped log entry to state and debugPrint
  void _log(String level, String msg) {
    final ts = DateTime.now().toString().substring(11, 23); // HH:mm:ss.mmm
    final entry = '[$ts] $level: $msg';
    debugPrint('[Agent] $msg');
    state = state.copyWith(logs: [...state.logs, entry]);
  }

  Future<void> init() async {
    final initSw = Stopwatch()..start();
    _log('INFO', 'init start, agentId=$_agentId');
    try {
      // Load agent info
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId,
          orElse: () => throw Exception('Agent not found'));
      final agentCfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
      _log('INFO', 'loaded agent: name=${agent.name}, type=${agent.type}');

      // Load history messages
      final rows = await _db.getMessages(_agentId, limit: 50);
      final isTranslate = agent.type == 'ast-translate' || agent.type == 'translate';
      final rawMessages = rows.reversed.toList();
      final messages = <AgentMessage>[];

      if (isTranslate) {
        // 翻译类 Agent：配对连续的 user + assistant 消息为双语气泡
        int i = 0;
        while (i < rawMessages.length) {
          final r = rawMessages[i];
          if (r.role == 'user' && i + 1 < rawMessages.length && rawMessages[i + 1].role == 'assistant') {
            final trans = rawMessages[i + 1];
            messages.add(AgentMessage(
              id: r.id,
              role: r.role,
              content: r.content,
              status: r.status,
              translatedContent: trans.content,
              detectedLang: _detectLang(r.content),
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ));
            i += 2; // skip the paired assistant message
          } else {
            messages.add(AgentMessage(
              id: r.id,
              role: r.role,
              content: r.content,
              status: r.status,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ));
            i++;
          }
        }
        _log('INFO', 'loaded ${rawMessages.length} rows → ${messages.length} paired messages');
      } else {
        for (final r in rawMessages) {
          messages.add(AgentMessage(
            id: r.id,
            role: r.role,
            content: r.content,
            status: r.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
          ));
        }
      }

      final sessionId = 'session_$_agentId';

      // Listen to Native events (agents_server uses agentId as sessionId)
      _eventSub = _bridge.eventStream
          .where((e) => e.sessionId == _agentId)
          .listen(_handleEvent);

      // Load referenced service configs
      final allServices = await _db.getAllServiceConfigs();

      String svcCfg(String? id) {
        if (id == null) return '{}';
        try {
          return allServices.firstWhere((s) => s.id == id).configJson;
        } catch (_) {
          return '{}';
        }
      }

      /// 注入 STT 配置：
      ///  - `language` = 当前活动源语言（单语模式时用它）
      ///  - `languages` = 候选数组（≥2 个时启用 AutoDetect；否则 key 删除）
      String buildSttConfigJson(
        String? id,
        String activeLang,
        List<String> langs,
      ) {
        final base = svcCfg(id);
        try {
          final map = jsonDecode(base) as Map<String, dynamic>;
          if (activeLang.isNotEmpty) map['language'] = activeLang;
          if (langs.length >= 2) {
            map['languages'] = langs;
          } else {
            map.remove('languages');
          }
          return jsonEncode(map);
        } catch (_) {
          return base;
        }
      }
      String svcVendor(String? id) {
        if (id == null) return '';
        try {
          return allServices.firstWhere((s) => s.id == id).vendor;
        } catch (_) {
          return '';
        }
      }

      String svcName(String? id) {
        if (id == null) return '';
        try {
          return allServices.firstWhere((s) => s.id == id).name;
        } catch (_) {
          return '';
        }
      }

      final llmId = agentCfg['llmServiceId'] as String?;
      final sttId = agentCfg['sttServiceId'] as String?;
      final ttsId = agentCfg['ttsServiceId'] as String?;
      final stsId = agentCfg['stsServiceId'] as String?;
      final astId = agentCfg['astServiceId'] as String?;
      final translationId = agentCfg['translationServiceId'] as String?;
      // Read supported language lists with fallback. 旧库可能存的是 'zh'/'en' 这种短码，
      // 这里统一过 LocaleService.toCanonical 归一到 zh-CN/en-US。
      final srcLangsList = (agentCfg['srcLangs'] as List?)?.cast<String>();
      final dstLangsList = (agentCfg['dstLangs'] as List?)?.cast<String>();
      final srcLangs = LocaleService.toCanonicalAll(
        srcLangsList ?? [agentCfg['srcLang'] as String? ?? 'zh-CN'],
      );
      final dstLangs = LocaleService.toCanonicalAll(
        dstLangsList ?? [agentCfg['dstLang'] as String? ?? 'en-US'],
      );
      var srcLang = LocaleService.toCanonical(
        agentCfg['srcLang'] as String? ?? srcLangs.first,
      );
      var dstLang = LocaleService.toCanonical(
        agentCfg['dstLang'] as String? ?? dstLangs.first,
      );

      // Agent type 直接决定模式，不再做 effectiveType 转换
      final agentType = agent.type;
      final isE2E = agentType == 'sts-chat' || agentType == 'ast-translate';

      // AST 不支持 auto 语言，降级为第一个真实语言
      if (agentType == 'ast-translate' && srcLang == 'auto') {
        srcLang = srcLangs.firstWhere((l) => l != 'auto', orElse: () => 'zh-CN');
        _log('INFO', 'AST: srcLang "auto" not supported, fallback to "$srcLang"');
      }

      final e2eServiceId = agentType == 'ast-translate' ? astId : stsId;

      // 把 Agent 级别的 LLM 偏好（如 enableThinking）合入 LLM 服务的配置 JSON
      String buildLlmConfigJson(String? serviceId) {
        final base = svcCfg(serviceId);
        final map = jsonDecode(base) as Map<String, dynamic>;
        final v = agentCfg['enableThinking'];
        if (v != null) map['enableThinking'] = v;
        return jsonEncode(map);
      }

      // Build E2E config — 从 ServiceConfigDto 读取凭证，注入语言和 agentId
      String buildE2eConfigJson(String? serviceId) {
        final base = svcCfg(serviceId);
        final map = jsonDecode(base) as Map<String, dynamic>;
        map['srcLang'] = srcLang;
        map['dstLang'] = dstLang;
        // 注入 Agent 特有的 agentId（polychat 远端 Agent 需要）
        final agentRemoteId = agentCfg['agentId'] as String?;
        if (agentRemoteId != null) {
          map['agentId'] = agentRemoteId;
        }
        return jsonEncode(map);
      }

      String resolveE2eVendor() {
        final id = agentType == 'ast-translate' ? astId : stsId;
        return svcVendor(id);
      }

      String resolveE2eServiceName() {
        return svcName(e2eServiceId ?? llmId);
      }

      _log('INFO', 'agentType=$agentType, isE2E=$isE2E, srcLang=$srcLang, dstLang=$dstLang');
      _log('INFO', 'services: llm=${svcName(llmId)}, stt=${svcName(sttId)}, tts=${svcName(ttsId)}, sts=${svcName(stsId)}, ast=${svcName(astId)}, translation=${svcName(translationId)}');

      // Read persisted bidirectional / direction (translate agent only).
      final persistedBidi = agentCfg['bidirectional'] == true;
      final persistedDir = (agentCfg['translateDirection'] as String?) ?? 'src_to_dst';
      final sttVendorStr = svcVendor(sttId);
      // 厂商是否原生支持语种检测（与 bidirectional 是否实际开启无关，仅决定 UI 是否暴露开关）。
      final sttSupportsDetect =
          _SttCapability.supportsLanguageDetection(sttVendorStr);
      // 互译开 + 厂商支持 → AutoDetect 候选 = {srcLang, dstLang}（剔除 auto）。
      // 互译关 + srcLang=='auto' + 厂商支持 → AutoDetect 候选 = srcLangs（剔除 auto），
      //   "原语言识别" 但用户选了"自动检测"——必须走 AutoDetect，否则把 'auto' 当成
      //   单语 language 喂给厂商会导致 STT 静默失败（Azure 不接受 'auto' 作为
      //   speechRecognitionLanguage）。
      // 其它情况走单语模式（按 cfg.language=srcLang）。
      final effectiveBidi = persistedBidi && sttSupportsDetect;
      final List<String> sttLanguages;
      if (effectiveBidi) {
        sttLanguages = <String>{srcLang, dstLang}
            .where((l) => l.isNotEmpty && l != 'auto')
            .toList();
      } else if (srcLang == 'auto' && sttSupportsDetect) {
        sttLanguages =
            srcLangs.where((l) => l.isNotEmpty && l != 'auto').toList();
      } else {
        sttLanguages = <String>[]; // 空数组 → STT 单语模式
      }
      _log('INFO',
          'sttLanguages=$sttLanguages supportsDetect=$sttSupportsDetect '
          'bidirectional=$effectiveBidi');

      state = state.copyWith(
        sessionId: sessionId,
        messages: messages,
        agentName: agent.name,
        agentType: agentType,
        inputMode: isE2E ? 'call' : 'text',
        connectionState: ServiceConnectionState.disconnected,
        srcLang: srcLang,
        dstLang: dstLang,
        srcLangs: srcLangs,
        dstLangs: dstLangs,
        bidirectional: persistedBidi && sttSupportsDetect,
        translateDirection: persistedDir,
        sttSupportsLanguageDetection: sttSupportsDetect,
        llmServiceName: resolveE2eServiceName(),
        sttServiceName: svcName(sttId),
        ttsServiceName: svcName(ttsId),
      );

      // Create native agent via agents_server
      try {
        final e2eVendor = resolveE2eVendor();
        // 缓存除 STT/extraParams 之外的不变量，互译切换时复用。
        _cachedSttId = sttId;
        _cachedSttBaseJson = svcCfg(sttId);
        _createAgentArgs = {
          'agentType': agentType,
          'inputMode': isE2E ? 'call' : 'text',
          'sttVendor': svcVendor(sttId).isNotEmpty ? svcVendor(sttId) : null,
          'ttsVendor': svcVendor(ttsId).isNotEmpty ? svcVendor(ttsId) : null,
          'llmVendor': svcVendor(llmId).isNotEmpty ? svcVendor(llmId) : null,
          'stsVendor': (agentType == 'sts-chat' && e2eVendor.isNotEmpty)
              ? e2eVendor : null,
          'astVendor': (agentType == 'ast-translate' && e2eVendor.isNotEmpty)
              ? e2eVendor : null,
          'translationVendor':
              svcVendor(translationId).isNotEmpty ? svcVendor(translationId) : null,
          'translationConfigJson': svcCfg(translationId),
          'ttsConfigJson': svcCfg(ttsId),
          'llmConfigJson': buildLlmConfigJson(llmId),
          'stsConfigJson':
              agentType == 'sts-chat' ? buildE2eConfigJson(stsId) : null,
          'astConfigJson':
              agentType == 'ast-translate' ? buildE2eConfigJson(astId) : null,
        };

        await _bridge.createAgent(
          agentId: _agentId,
          agentType: agentType,
          inputMode: isE2E ? 'call' : 'text',
          sttVendor: _createAgentArgs!['sttVendor'] as String?,
          ttsVendor: _createAgentArgs!['ttsVendor'] as String?,
          llmVendor: _createAgentArgs!['llmVendor'] as String?,
          stsVendor: _createAgentArgs!['stsVendor'] as String?,
          astVendor: _createAgentArgs!['astVendor'] as String?,
          translationVendor: _createAgentArgs!['translationVendor'] as String?,
          translationConfigJson:
              _createAgentArgs!['translationConfigJson'] as String?,
          sttConfigJson: buildSttConfigJson(sttId, srcLang, sttLanguages),
          ttsConfigJson: _createAgentArgs!['ttsConfigJson'] as String?,
          llmConfigJson: _createAgentArgs!['llmConfigJson'] as String?,
          stsConfigJson: _createAgentArgs!['stsConfigJson'] as String?,
          astConfigJson: _createAgentArgs!['astConfigJson'] as String?,
          extraParams: {
            'srcLang': srcLang,
            'dstLang': dstLang,
            'source_lang': srcLang,
            'target_lang': dstLang,
            if (agentType == 'translate') ...{
              'bidirectional': effectiveBidi.toString(),
              'direction': persistedDir,
            },
          },
        );
        _log('INFO', 'createAgent OK in ${initSw.elapsedMilliseconds}ms: type=$agentType e2eSvc=$e2eServiceId');

        // 端到端 Agent 不再自动连接，由用户手动点击连接
        if (isE2E) {
          _log('INFO', 'E2E agent ready, waiting for manual connect');
        }
      } catch (e) {
        _log('ERROR', 'createAgent failed: $e');
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        final msgs = List<AgentMessage>.from(state.messages)
          ..add(AgentMessage(
            id: 'create_err_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: 'Agent 创建失败: $errMsg',
            status: 'error',
          ));
        state = state.copyWith(
          messages: msgs,
          connectionState: isE2E ? ServiceConnectionState.error : state.connectionState,
        );
      }
    } catch (e) {
      _log('ERROR', 'init failed: $e');
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      final msgs = List<AgentMessage>.from(state.messages)
        ..add(AgentMessage(
          id: 'init_err_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: '初始化失败: $errMsg',
          status: 'error',
        ));
      state = state.copyWith(messages: msgs);
    }
  }

  Future<void> _handleEvent(AgentEvent event) async {
    switch (event) {
      // 使用 `state: agentState` 把字段重命名，避免遮蔽 StateNotifier.state
      case SessionStateEvent(state: final agentState):
        _log('EVENT', 'sessionState → $agentState');
        state = state.copyWith(sessionState: agentState);

      case SttEvent(:final kind, :final text, :final detectedLang, :final requestId):
        if (kind == SttEventKind.partialResult) {
          if (state.inputMode == 'call' && (text ?? '').isNotEmpty) {
            // call 模式（端到端 / 三段式通用）：实时更新用户气泡
            final msgs = List<AgentMessage>.from(state.messages);
            final existingIdx = msgs.lastIndexWhere(
                (m) => m.role == 'user' && m.status == 'streaming');
            if (existingIdx != -1) {
              msgs[existingIdx].content = text!;
            } else {
              final msgId = state.isTranslateMode
                  ? 'ast_src_${DateTime.now().millisecondsSinceEpoch}'
                  : (state.isEndToEnd
                      ? 'sts_user_${DateTime.now().millisecondsSinceEpoch}'
                      : 'call_user_${DateTime.now().millisecondsSinceEpoch}');
              msgs.add(AgentMessage(
                id: msgId,
                role: 'user',
                content: text!,
                status: 'streaming',
                // 三段式 translate 的 detectedLang 决定 UI 左右站位：
                //   - 互译关 + srcLang 是具体语言：单语模式，强制打成 srcLang
                //     （= 自然全部右侧"我"，无需依赖 STT 是否给 detectedLang）
                //   - 互译开（或 srcLang=='auto'）+ 厂商支持 detection：信任 STT 的；
                //     partial 阶段可能为 null，留待 finalResult 时定稿，避免 CJK 启发式误判
                //   - 否则回退启发式（厂商不支持 detection 时兜底）
                detectedLang: state.isTranslateMode
                    ? (!state.bidirectional && state.srcLang != 'auto'
                        ? state.srcLang
                        : (state.sttSupportsLanguageDetection
                            ? detectedLang
                            : _detectLang(text)))
                    : null,
              ));
            }
            state = state.copyWith(messages: msgs, sttPartial: text ?? '');
          } else {
            // 非 call 模式：只更新预览文字（push-to-talk）
            state = state.copyWith(sttPartial: text ?? '');
          }
        } else if (kind == SttEventKind.finalResult) {
          // call 模式：定稿用户识别文字（端到端 / 三段式通用）
          if (state.inputMode == 'call' && (text ?? '').isNotEmpty) {
            final msgs = List<AgentMessage>.from(state.messages);
            // 找到正在 streaming 的 user 气泡，标记为 done
            final existingIdx = msgs.lastIndexWhere(
                (m) => m.role == 'user' && m.status == 'streaming');
            String? finalDetected;
            if (state.isTranslateMode) {
              // 同 partial 路径的 detectedLang 解析规则。
              if (!state.bidirectional && state.srcLang != 'auto') {
                finalDetected = state.srcLang;
              } else if (state.sttSupportsLanguageDetection) {
                finalDetected = detectedLang ?? _detectLang(text!);
              } else {
                finalDetected = detectedLang ?? _detectLang(text!);
              }
            }
            // 三段式翻译要求 user 气泡 id == native finalResult.requestId，
            // 这样后续 LLM firstToken/done(requestId=同) 才能配对，把译文写入
            // user 气泡的 translatedContent。否则会另起一个空 assistant 气泡。
            // AgentMessage.id 是 final，必须 replace 整条。
            if (existingIdx != -1) {
              final old = msgs[existingIdx];
              final newId =
                  (state.isTranslateMode && requestId.isNotEmpty)
                      ? requestId
                      : old.id;
              msgs[existingIdx] = AgentMessage(
                id: newId,
                role: old.role,
                content: text!,
                status: 'done',
                translatedContent: old.translatedContent,
                detectedLang: state.isTranslateMode && finalDetected != null
                    ? finalDetected
                    : old.detectedLang,
                createdAt: old.createdAt,
              );
            } else {
              final msgId = state.isTranslateMode
                  ? (requestId.isNotEmpty
                      ? requestId
                      : 'ast_src_${DateTime.now().millisecondsSinceEpoch}')
                  : 'sts_user_${DateTime.now().millisecondsSinceEpoch}';
              msgs.add(AgentMessage(
                id: msgId,
                role: 'user',
                content: text!,
                status: 'done',
                detectedLang: finalDetected,
              ));
            }
            _log('EVENT', 'STT finalResult → user msg: "${text!.substring(0, text.length.clamp(0, 40))}"');
            state = state.copyWith(messages: msgs, sttPartial: '');
          } else {
            // 非 STS 模式：暂存最终识别文本，松开时再发送
            state = state.copyWith(
              sttPartial: text ?? '',
              pendingVoiceText: text ?? '',
            );
          }
        } else if (kind == SttEventKind.listeningStopped) {
          // 松开后 STT 停止：移除气泡，若未取消则发送
          // fallback to sttPartial in case finalResult arrived after listeningStopped
          final pending = state.pendingVoiceText.isNotEmpty
              ? state.pendingVoiceText
              : state.sttPartial;
          final msgs = List<AgentMessage>.from(state.messages)
            ..removeWhere((m) => m.id == state.recordingMsgId);
          state = state.copyWith(
            sttPartial: '',
            pendingVoiceText: '',
            messages: msgs,
            recordingMsgId: null,
          );
          if (!_voiceCancelled && pending.isNotEmpty) {
            final requestId = 'voice_${DateTime.now().millisecondsSinceEpoch}';
            final sendMsgs = List<AgentMessage>.from(state.messages)
              ..add(AgentMessage(
                  id: requestId, role: 'user', content: pending, status: 'done'));
            state = state.copyWith(messages: sendMsgs);
            await _bridge.sendText(_agentId, requestId, pending);
          }
          _voiceCancelled = false;
        }

      case LlmEvent(:final kind, :final requestId, :final textDelta, :final fullText, :final errorMessage):
        final msgs = List<AgentMessage>.from(state.messages);
        final idx = msgs.indexWhere((m) => m.id == requestId && m.role == 'assistant');

        // Helper: ensure assistant placeholder exists for this request
        void ensureAssistant(String status, String content) {
          if (idx == -1) {
            msgs.add(AgentMessage(id: requestId, role: 'assistant', content: content, status: status));
          } else {
            msgs[idx].content = content.isNotEmpty ? msgs[idx].content + content : msgs[idx].content;
            msgs[idx].status = status;
          }
        }

        if (kind == LlmEventKind.firstToken && textDelta != null) {
          if (state.isTranslateMode && state.isEndToEnd) {
            // AST 翻译模式：译文写入最近一条 user 消息的 translatedContent
            final userIdx = msgs.lastIndexWhere(
              (m) => m.role == 'user' && m.detectedLang != null);
            if (userIdx != -1) {
              msgs[userIdx].translatedContent = textDelta;
              _log('EVENT', 'LLM firstToken → paired translation: "${textDelta.substring(0, textDelta.length.clamp(0, 30))}"');
            }
          } else if (state.isTranslateMode) {
            // 三段式翻译：把译文配对到同 requestId 的 user 气泡上（左右与 detectedLang 一致）
            final userIdx =
                msgs.indexWhere((m) => m.id == requestId && m.role == 'user');
            if (userIdx != -1) {
              msgs[userIdx].translatedContent =
                  (msgs[userIdx].translatedContent ?? '') + textDelta;
            } else if (idx == -1) {
              msgs.add(AgentMessage(
                  id: requestId, role: 'assistant',
                  content: textDelta, status: 'streaming'));
            } else {
              msgs[idx].content += textDelta;
              msgs[idx].status = 'streaming';
            }
          } else if (idx == -1) {
            msgs.add(AgentMessage(id: requestId, role: 'assistant', content: textDelta, status: 'streaming'));
          } else {
            // textDelta 始终是增量片段：
            //   - 三段式 LLM：每次回调一个 token delta
            //   - STS 端到端：web 桥已把 cumulative 快照转成 delta，Android 桥按句下发
            msgs[idx].content += textDelta;
            msgs[idx].status = 'streaming';
          }
        } else if (kind == LlmEventKind.done) {
          if (state.isTranslateMode && state.isEndToEnd) {
            // AST 翻译模式：done 只是标记翻译完成，不需要额外处理
            _log('EVENT', 'LLM done → translation round complete');
          } else if (state.isTranslateMode) {
            // 三段式翻译 done：用 fullText 兜底（以防 firstToken 被缓存或丢失）
            final userIdx =
                msgs.indexWhere((m) => m.id == requestId && m.role == 'user');
            if (userIdx != -1) {
              if (fullText != null && fullText.isNotEmpty) {
                msgs[userIdx].translatedContent = fullText;
              }
            } else if (idx != -1) {
              msgs[idx].status = 'done';
            }
          } else if (idx != -1) {
            msgs[idx].status = 'done';
          }
        } else if (kind == LlmEventKind.cancelled) {
          if (idx != -1) msgs[idx].status = 'cancelled';
        } else if (kind == LlmEventKind.error) {
          ensureAssistant('error', errorMessage ?? '');
        }
        state = state.copyWith(messages: msgs);

      case ServiceConnectionStateEvent(:final connectionState, :final errorMessage):
        _log(connectionState == ServiceConnectionState.error ? 'ERROR' : 'EVENT',
            'connectionState → $connectionState${errorMessage != null ? ' ($errorMessage)' : ''}');
        state = state.copyWith(connectionState: connectionState);
        if (connectionState == ServiceConnectionState.error && errorMessage != null) {
          final msgs = List<AgentMessage>.from(state.messages)
            ..add(AgentMessage(
              id: 'conn_err_${DateTime.now().millisecondsSinceEpoch}',
              role: 'assistant',
              content: '连接失败: $errorMessage',
              status: 'error',
            ));
          state = state.copyWith(messages: msgs);
        }

      case AgentErrorEvent(:final errorCode, :final message):
        _log('ERROR', 'AgentError: [$errorCode] $message');
        final msgs = List<AgentMessage>.from(state.messages)
          ..add(AgentMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: '[$errorCode] $message',
            status: 'error',
          ));
        state = state.copyWith(messages: msgs);

      default:
        break;
    }
  }

  // ─── 端到端连接控制 ──────────────────────────────────────────────────────

  Future<void> connectService() async {
    if (!state.isEndToEnd) return;
    state = state.copyWith(connectionState: ServiceConnectionState.connecting);
    try {
      await _bridge.connectService(_agentId);
    } catch (e) {
      _log('ERROR', 'connectService failed: $e');
      state = state.copyWith(connectionState: ServiceConnectionState.error);
    }
  }

  Future<void> disconnectService() async {
    if (!state.isEndToEnd) return;
    await _bridge.disconnectService(_agentId);
    state = state.copyWith(connectionState: ServiceConnectionState.disconnected);
  }

  /// 暂停音频传输（端到端挂断时调用），切到 short_voice 模式
  Future<void> pauseAudio() async {
    if (!state.isEndToEnd) return;
    await _bridge.pauseAudio(_agentId);
    state = state.copyWith(inputMode: 'short_voice');
  }

  /// 恢复音频传输（端到端恢复通话时调用），切到 call 模式
  Future<void> resumeAudio() async {
    if (!state.isEndToEnd) return;
    await _bridge.resumeAudio(_agentId);
    state = state.copyWith(inputMode: 'call');
  }

  Future<void> sendText(String requestId, String text) async {
    // 翻译模式：根据当前方向给 user 气泡打 detectedLang，
    // 让 _TranslationPairCard 按 detectedLang 决定左右站位。
    String? detected;
    if (state.isTranslateMode) {
      detected = state.translateDirection == 'dst_to_src'
          ? state.dstLang
          : state.srcLang;
    }
    final msgs = List<AgentMessage>.from(state.messages)
      ..add(AgentMessage(
        id: requestId,
        role: 'user',
        content: text,
        status: 'done',
        detectedLang: detected,
      ));
    state = state.copyWith(messages: msgs);
    await _bridge.sendText(_agentId, requestId, text);
  }

  Future<void> setInputMode(String mode) async {
    // 端到端模式禁止切到 text
    if (state.isEndToEnd && mode == 'text') return;

    // 端到端模式切换：call ↔ short_voice 需要控制音频流
    if (state.isEndToEnd) {
      if (state.inputMode == 'call' && mode == 'short_voice') {
        // 挂断：暂停持续音频流
        await _bridge.pauseAudio(_agentId);
      } else if (state.inputMode == 'short_voice' && mode == 'call') {
        // 恢复通话：恢复持续音频流
        await _bridge.resumeAudio(_agentId);
      }
    }

    state = state.copyWith(inputMode: mode);
    await _bridge.setInputMode(_agentId, mode);
  }

  Future<void> startListening() async {
    // 立即打断当前 AI 回复（停止 LLM + TTS）
    await _bridge.interrupt(_agentId);
    // 添加临时录音气泡
    final recId = 'recording_${DateTime.now().millisecondsSinceEpoch}';
    final msgs = List<AgentMessage>.from(state.messages)
      ..add(AgentMessage(id: recId, role: 'user', content: '', status: 'recording'));
    state = state.copyWith(messages: msgs, recordingMsgId: recId, pendingVoiceText: '', sttPartial: '');
    await _bridge.startListening(_agentId);
  }

  Future<void> stopListening() {
    _voiceCancelled = false;
    return _bridge.stopListening(_agentId);
  }

  Future<void> cancelListening() async {
    _voiceCancelled = true;
    // 立即移除录音气泡，清空状态
    if (state.recordingMsgId != null) {
      final msgs = List<AgentMessage>.from(state.messages)
        ..removeWhere((m) => m.id == state.recordingMsgId);
      state = state.copyWith(
        sttPartial: '',
        pendingVoiceText: '',
        messages: msgs,
        recordingMsgId: null,
      );
    }
    await _bridge.stopListening(_agentId);
  }

  Future<void> swapLanguages() async {
    final src = state.srcLang;
    final dst = state.dstLang;
    state = state.copyWith(srcLang: dst, dstLang: src);
    await _persistLanguages(dst, src);
  }

  /// 设置会话语言（STS 聊天模式：同时设置 src 和 dst）
  Future<void> setConversationLang(String lang) async {
    state = state.copyWith(srcLang: lang, dstLang: lang);
    await _persistLanguages(lang, lang);
  }

  Future<void> setSrcLang(String lang) async {
    state = state.copyWith(srcLang: lang);
    await _persistLanguages(lang, state.dstLang);
  }

  Future<void> setDstLang(String lang) async {
    state = state.copyWith(dstLang: lang);
    await _persistLanguages(state.srcLang, lang);
  }

  /// 通过 CJK 字符占比检测文本语言（返回 canonical 码）
  static String _detectLang(String text) {
    final cjk = text.runes.where((c) => c >= 0x4e00 && c <= 0x9fff).length;
    final total = text.runes.where((c) => c > 0x20).length;
    return (total == 0 || cjk / total > 0.3) ? 'zh-CN' : 'en-US';
  }

  Future<void> _persistLanguages(String src, String dst) async {
    try {
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId);
      final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
      cfg['srcLang'] = src;
      cfg['dstLang'] = dst;
      await _db.upsertAgent(AgentDto(
        id: agent.id,
        name: agent.name,
        type: agent.type,
        configJson: jsonEncode(cfg),
        createdAt: agent.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  /// 切换互译开关（仅 STT 支持语言识别时生效）。
  /// 互译开 → STT 候选 [srcLang, dstLang]；互译关 → STT 单语模式 [srcLang]。
  /// 因为 Azure 候选列表只能在 SpeechRecognizer 构造时确定，需要 stop+recreate。
  Future<void> setBidirectional(bool on) async {
    if (!state.sttSupportsLanguageDetection && on) return;
    state = state.copyWith(bidirectional: on);
    await _persistTranslateOption('bidirectional', on);
    await _bridge.setAgentOption(_agentId, 'bidirectional', on.toString());

    // 重建 native agent，以让 STT 在新候选列表下重新初始化。
    await _rebuildNativeAgent();
  }

  /// 用当前 state（srcLang/dstLang/bidirectional/direction）重建 native agent。
  /// 仅在缓存了 createAgent 入参后才执行；UI 状态不动。
  Future<void> _rebuildNativeAgent() async {
    final args = _createAgentArgs;
    if (args == null) return;
    final agentType = args['agentType'] as String;
    final inputMode = args['inputMode'] as String;
    // 与 init 路径一致：互译关 + srcLang=='auto' + 厂商支持 → 仍要走 AutoDetect，
    // 否则会把 'auto' 当成 STT 单语 language 喂进去导致静默失败。
    final List<String> sttLanguages;
    if (state.bidirectional) {
      sttLanguages = <String>{state.srcLang, state.dstLang}
          .where((l) => l.isNotEmpty && l != 'auto')
          .toList();
    } else if (state.srcLang == 'auto' && state.sttSupportsLanguageDetection) {
      sttLanguages = state.srcLangs
          .where((l) => l.isNotEmpty && l != 'auto')
          .toList();
    } else {
      sttLanguages = <String>[];
    }

    try {
      await _bridge.stopAgent(_agentId);
    } catch (_) {}
    await _bridge.createAgent(
      agentId: _agentId,
      agentType: agentType,
      inputMode: inputMode,
      sttVendor: args['sttVendor'] as String?,
      ttsVendor: args['ttsVendor'] as String?,
      llmVendor: args['llmVendor'] as String?,
      stsVendor: args['stsVendor'] as String?,
      astVendor: args['astVendor'] as String?,
      translationVendor: args['translationVendor'] as String?,
      translationConfigJson: args['translationConfigJson'] as String?,
      sttConfigJson: _buildSttConfigJsonStandalone(
          _cachedSttId, state.srcLang, sttLanguages),
      ttsConfigJson: args['ttsConfigJson'] as String?,
      llmConfigJson: args['llmConfigJson'] as String?,
      stsConfigJson: args['stsConfigJson'] as String?,
      astConfigJson: args['astConfigJson'] as String?,
      extraParams: {
        'srcLang': state.srcLang,
        'dstLang': state.dstLang,
        'source_lang': state.srcLang,
        'target_lang': state.dstLang,
        if (agentType == 'translate') ...{
          'bidirectional': state.bidirectional.toString(),
          'direction': state.translateDirection,
        },
      },
    );
    _log('INFO',
        'rebuilt native agent: bidi=${state.bidirectional} '
        'sttLanguages=$sttLanguages');
  }

  String _buildSttConfigJsonFromBase(
      String base, String activeLang, List<String> langs) {
    try {
      final map = jsonDecode(base) as Map<String, dynamic>;
      if (activeLang.isNotEmpty) map['language'] = activeLang;
      if (langs.length >= 2) {
        map['languages'] = langs;
      } else {
        map.remove('languages');
      }
      return jsonEncode(map);
    } catch (_) {
      return base;
    }
  }

  /// Wrapper that fetches the base STT config JSON synchronously-ish via cached args.
  String _buildSttConfigJsonStandalone(
      String? sttId, String activeLang, List<String> langs) {
    // 重建场景下从异步加载结果同步构建：先读 base（同步缓存里），再注入。
    // 简化：直接用 langs/activeLang 包成最小 JSON——下游 STT 服务会与原配置合并。
    // 但 Azure 服务在 initialize 阶段会替换 apiKey/region，所以这里必须保留它们。
    // 使用 _cachedSttBaseJson 兜底（init 阶段填好）。
    final base = _cachedSttBaseJson ?? '{}';
    return _buildSttConfigJsonFromBase(base, activeLang, langs);
  }

  String? _cachedSttBaseJson;

  /// 切换文本输入方向（src_to_dst | dst_to_src）
  Future<void> setTranslateDirection(String direction) async {
    final norm = direction == 'dst_to_src' ? 'dst_to_src' : 'src_to_dst';
    state = state.copyWith(translateDirection: norm);
    await _bridge.setAgentOption(_agentId, 'direction', norm);
    await _persistTranslateOption('translateDirection', norm);
  }

  Future<void> toggleTranslateDirection() async {
    final next = state.translateDirection == 'src_to_dst'
        ? 'dst_to_src'
        : 'src_to_dst';
    await setTranslateDirection(next);
  }

  Future<void> _persistTranslateOption(String key, Object value) async {
    try {
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId);
      final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
      cfg[key] = value;
      await _db.upsertAgent(AgentDto(
        id: agent.id,
        name: agent.name,
        type: agent.type,
        configJson: jsonEncode(cfg),
        createdAt: agent.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    await LocalDbBridge().deleteMessages(_agentId);
    state = state.copyWith(messages: []);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    // 退出时停止 Agent（释放服务资源、断开连接）
    _bridge.stopAgent(_agentId).ignore();
    super.dispose();
  }
}

/// STT 厂商能力静态表（与 native/web 各 vendor 的
/// `supportsLanguageDetection` 声明保持一致）。
class _SttCapability {
  static bool supportsLanguageDetection(String vendor) {
    switch (vendor) {
      // Azure 通过 AutoDetectSourceLanguageConfig 支持识别（最多 4 种候选）。
      case 'azure':
        return true;
      default:
        return false;
    }
  }
}
