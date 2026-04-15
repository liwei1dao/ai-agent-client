import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'package:uuid/uuid.dart';
import '../voitrans_api.dart';
import 'config_service.dart';

final polychatServiceProvider = Provider((ref) => PolychatService());

class PolychatService {
  final _db = LocalDbBridge();
  final _uuid = const Uuid();

  /// 同步远端 Agent 到本地：
  /// 1. 创建/更新共享的 PolyChat 服务容器（STS 和 AST 各最多一个）
  /// 2. 为每个远端 Agent 创建 AgentDto，引用共享服务 + 自身 agentId
  /// 3. 清理远端已删除的 Agent，若无 Agent 引用则删除共享服务
  ///
  /// 返回同步的 Agent 数量。
  Future<int> syncAgents(PolychatConfig config) async {
    if (!config.isConfigured) {
      throw Exception('请先填写 PolyChat 平台配置');
    }

    final client = PolychatApiClient(
      baseUrl: config.baseUrl,
      appId: config.appId,
      appSecret: config.appSecret,
    );

    final remoteAgents = await client.fetchAgents();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 平台凭证（服务容器只存这些，不含 agentId）
    final credentialsJson = jsonEncode({
      'baseUrl': config.baseUrl,
      'appId': config.appId,
      'appSecret': config.appSecret,
    });

    // 获取现有数据
    final allServices = await _db.getAllServiceConfigs();
    final allAgents = await _db.getAllAgents();

    // 查找已有的 polychat 共享服务（按 type + vendor 匹配）
    final existingStsService = allServices
        .where((s) => s.type == 'sts' && s.vendor == 'polychat')
        .toList();
    final existingAstService = allServices
        .where((s) => s.type == 'ast' && s.vendor == 'polychat')
        .toList();

    // 查找已有的 polychat Agent（通过 tags 匹配）
    final existingPcAgents = allAgents.where((a) {
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        final tags = (cfg['tags'] as List?)?.cast<String>() ?? [];
        return tags.contains('polychat');
      } catch (_) {
        return false;
      }
    }).toList();

    // 分类远端 Agent
    bool needsStsService = false;
    bool needsAstService = false;
    for (final remote in remoteAgents) {
      switch (remote.type) {
        case 'sts-chat':
        case 'chat':
          needsStsService = true;
          break;
        case 'ast-translate':
        case 'translate':
          needsAstService = true;
          break;
      }
    }

    // ── 创建/更新共享服务容器 ──
    String? stsServiceId;
    if (needsStsService) {
      if (existingStsService.isNotEmpty) {
        stsServiceId = existingStsService.first.id;
        await _db.upsertServiceConfig(ServiceConfigDto(
          id: stsServiceId,
          type: 'sts',
          vendor: 'polychat',
          name: 'PolyChat STS',
          configJson: credentialsJson,
          createdAt: existingStsService.first.createdAt,
        ));
      } else {
        stsServiceId = _uuid.v4();
        await _db.upsertServiceConfig(ServiceConfigDto(
          id: stsServiceId,
          type: 'sts',
          vendor: 'polychat',
          name: 'PolyChat STS',
          configJson: credentialsJson,
          createdAt: now,
        ));
      }
    }

    String? astServiceId;
    if (needsAstService) {
      if (existingAstService.isNotEmpty) {
        astServiceId = existingAstService.first.id;
        await _db.upsertServiceConfig(ServiceConfigDto(
          id: astServiceId,
          type: 'ast',
          vendor: 'polychat',
          name: 'PolyChat AST',
          configJson: credentialsJson,
          createdAt: existingAstService.first.createdAt,
        ));
      } else {
        astServiceId = _uuid.v4();
        await _db.upsertServiceConfig(ServiceConfigDto(
          id: astServiceId,
          type: 'ast',
          vendor: 'polychat',
          name: 'PolyChat AST',
          configJson: credentialsJson,
          createdAt: now,
        ));
      }
    }

    // ── 同步每个远端 Agent ──
    final syncedRemoteIds = <String>{};
    int synced = 0;

    for (final remote in remoteAgents) {
      syncedRemoteIds.add(remote.agentId);

      String agentType;
      String? serviceId;
      String serviceIdKey;
      switch (remote.type) {
        case 'sts-chat':
        case 'chat':
          agentType = 'sts-chat';
          serviceId = stsServiceId;
          serviceIdKey = 'stsServiceId';
          break;
        case 'ast-translate':
        case 'translate':
          agentType = 'ast-translate';
          serviceId = astServiceId;
          serviceIdKey = 'astServiceId';
          break;
        default:
          continue;
      }

      // Agent config：引用共享服务 + 自身 agentId
      final agentConfigMap = <String, dynamic>{
        'tags': ['polychat'],
        'agentId': remote.agentId,
        serviceIdKey: serviceId,
      };
      if (remote.supportedLangs.isNotEmpty) {
        agentConfigMap['srcLangs'] = remote.supportedLangs;
        agentConfigMap['dstLangs'] = remote.supportedLangs;
        agentConfigMap['srcLang'] = remote.supportedLangs.first;
        agentConfigMap['dstLang'] = remote.supportedLangs.length > 1
            ? remote.supportedLangs[1]
            : remote.supportedLangs.first;
      }

      // 查找已有 Agent（通过 agentId 匹配）
      final existingAgent = existingPcAgents.where((a) {
        try {
          final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
          return cfg['agentId'] == remote.agentId;
        } catch (_) {
          return false;
        }
      }).toList();

      if (existingAgent.isNotEmpty) {
        final ea = existingAgent.first;
        await _db.upsertAgent(AgentDto(
          id: ea.id,
          name: remote.name,
          type: agentType,
          configJson: jsonEncode(agentConfigMap),
          createdAt: ea.createdAt,
          updatedAt: now,
        ));
      } else {
        await _db.upsertAgent(AgentDto(
          id: _uuid.v4(),
          name: remote.name,
          type: agentType,
          configJson: jsonEncode(agentConfigMap),
          createdAt: now,
          updatedAt: now,
        ));
      }

      synced++;
    }

    // ── 清理远端已删除的 Agent ──
    for (final agent in existingPcAgents) {
      try {
        final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
        final agentRemoteId = cfg['agentId'] as String?;
        if (agentRemoteId != null &&
            !syncedRemoteIds.contains(agentRemoteId)) {
          await _db.deleteAgent(agent.id);
        }
      } catch (_) {
        await _db.deleteAgent(agent.id);
      }
    }

    // ── 清理不再需要的共享服务 ──
    if (!needsStsService && existingStsService.isNotEmpty) {
      await _db.deleteServiceConfig(existingStsService.first.id);
    }
    if (!needsAstService && existingAstService.isNotEmpty) {
      await _db.deleteServiceConfig(existingAstService.first.id);
    }

    return synced;
  }
}
