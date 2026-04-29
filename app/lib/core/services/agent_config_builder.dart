import 'dart:convert';

import 'package:local_db/local_db.dart';

import 'locale_service.dart';

/// 把一个 [AgentDto] + 它引用的 [ServiceConfigDto] 列表 + 语言对，组装成
/// `NativeAgentConfig.fromMap` 接受的 map 形状。
///
/// 与 [agent_screen_provider.dart] 里 `bridge.createAgent` 调用使用同一套字段——通话翻译
/// 走 [translate_server] 时不再用 agents_server 的 createAgent，但 native side
/// 用同一个 `NativeAgentConfig.fromMap` 解析，所以 map shape 必须一致。
class AgentConfigBuilder {
  AgentConfigBuilder({
    required this.agent,
    required this.allServices,
    required String srcLang,
    required String dstLang,
    this.inputMode = 'call',
  })  : srcLang = LocaleService.toCanonical(srcLang),
        dstLang = LocaleService.toCanonical(dstLang);

  final AgentDto agent;
  final List<ServiceConfigDto> allServices;
  final String srcLang;
  final String dstLang;
  final String inputMode;

  /// 当前实现：仅生成 `ast-translate` / `translate` 类型 agent 的 config（通话翻译
  /// 只支持这两类）。其它 agent type 请走 `agent_screen_provider` 的等价代码。
  Map<String, Object?> build() {
    final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;

    final llmId = cfg['llmServiceId'] as String?;
    final sttId = cfg['sttServiceId'] as String?;
    final ttsId = cfg['ttsServiceId'] as String?;
    final stsId = cfg['stsServiceId'] as String?;
    final astId = cfg['astServiceId'] as String?;
    final translationId = cfg['translationServiceId'] as String?;

    return <String, Object?>{
      'agentId': agent.id,
      'inputMode': inputMode,
      'sttVendor': _vendor(sttId),
      'ttsVendor': _vendor(ttsId),
      'llmVendor': _vendor(llmId),
      'stsVendor': agent.type == 'sts-chat' ? _vendor(stsId) : null,
      'astVendor': agent.type == 'ast-translate' ? _vendor(astId) : null,
      'translationVendor': _vendor(translationId),
      // 通话翻译每条腿的方向是固定的 (uplink=user→peer / downlink=peer→user)，
      // 不走 AutoDetect。把 srcLang 注入到 STT 的 `language` 字段，避免厂商默认
      // 配置（如 azure 的 zh-CN）覆盖 leg 自身的源语言。
      'sttConfigJson': _sttConfigJson(sttId),
      'ttsConfigJson': _cfgJson(ttsId),
      'llmConfigJson': _llmConfigJson(llmId, cfg),
      'stsConfigJson':
          agent.type == 'sts-chat' ? _e2eConfigJson(stsId, cfg) : null,
      'astConfigJson':
          agent.type == 'ast-translate' ? _e2eConfigJson(astId, cfg) : null,
      'translationConfigJson': _cfgJson(translationId),
      'extraParams': <String, String>{
        'srcLang': srcLang,
        'dstLang': dstLang,
        'source_lang': srcLang,
        'target_lang': dstLang,
      },
    };
  }

  String? _vendor(String? id) {
    if (id == null) return null;
    final v = allServices
        .where((s) => s.id == id)
        .map((s) => s.vendor)
        .firstOrNull;
    return (v == null || v.isEmpty) ? null : v;
  }

  String _cfgJson(String? id) {
    if (id == null) return '{}';
    return allServices
            .where((s) => s.id == id)
            .map((s) => s.configJson)
            .firstOrNull ??
        '{}';
  }

  /// STT 配置：注入本 leg 的源语言，覆盖服务默认 language；不启用 `languages`
  /// 数组（通话翻译每条腿方向固定，不需要 AutoDetect）。
  String _sttConfigJson(String? id) {
    final base = _cfgJson(id);
    try {
      final map = jsonDecode(base) as Map<String, dynamic>;
      if (srcLang.isNotEmpty) map['language'] = srcLang;
      map.remove('languages');
      return jsonEncode(map);
    } catch (_) {
      return base;
    }
  }

  String _llmConfigJson(String? id, Map<String, dynamic> agentCfg) {
    final base = jsonDecode(_cfgJson(id)) as Map<String, dynamic>;
    final v = agentCfg['enableThinking'];
    if (v != null) base['enableThinking'] = v;
    return jsonEncode(base);
  }

  /// E2E（AST/STS）服务的配置：把 srcLang/dstLang 注入到服务 config，便于
  /// volcengine AST 之类需要在握手前知道语向的协议正确建链。
  String _e2eConfigJson(String? id, Map<String, dynamic> agentCfg) {
    final base = jsonDecode(_cfgJson(id)) as Map<String, dynamic>;
    base['srcLang'] = srcLang;
    base['dstLang'] = dstLang;
    final remoteAgentId = agentCfg['agentId'] as String?;
    if (remoteAgentId != null) base['agentId'] = remoteAgentId;
    return jsonEncode(base);
  }
}

extension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
