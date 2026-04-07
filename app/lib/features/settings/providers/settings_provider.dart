import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_db/local_db.dart';
import '../../../core/voitrans_api.dart';

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.voitransBaseUrl = 'https://voitrans.ideapsound.com',
    this.voitransAppId = 'app_346bbeb6dc3bd37c',
    this.voitransAppSecret = 'sk_RJHRhzpost64qus5SCBlzECbPdMaiG_fcv7eJ-3u',
  });

  final ThemeMode themeMode;
  final String voitransBaseUrl;
  final String voitransAppId;
  final String voitransAppSecret;

  bool get isVoitransConfigured =>
      voitransBaseUrl.isNotEmpty &&
      voitransAppId.isNotEmpty &&
      voitransAppSecret.isNotEmpty;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? voitransBaseUrl,
    String? voitransAppId,
    String? voitransAppSecret,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        voitransBaseUrl: voitransBaseUrl ?? this.voitransBaseUrl,
        voitransAppId: voitransAppId ?? this.voitransAppId,
        voitransAppSecret: voitransAppSecret ?? this.voitransAppSecret,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('theme_mode') ?? ThemeMode.system.index;
    state = state.copyWith(
      themeMode: ThemeMode.values[index],
      voitransBaseUrl: prefs.getString('voitrans_base_url') ?? 'https://voitrans.ideapsound.com',
      voitransAppId: prefs.getString('voitrans_app_id') ?? 'app_346bbeb6dc3bd37c',
      voitransAppSecret: prefs.getString('voitrans_app_secret') ?? 'sk_RJHRhzpost64qus5SCBlzECbPdMaiG_fcv7eJ-3u',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setVoitransConfig({
    required String baseUrl,
    required String appId,
    required String appSecret,
  }) async {
    state = state.copyWith(
      voitransBaseUrl: baseUrl,
      voitransAppId: appId,
      voitransAppSecret: appSecret,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voitrans_base_url', baseUrl);
    await prefs.setString('voitrans_app_id', appId);
    await prefs.setString('voitrans_app_secret', appSecret);
  }

  /// 同步 VoiTrans 平台 Agent 到本地服务库和 Agent 库。
  /// 返回同步的 Agent 数量，出错则抛异常。
  Future<int> syncVoitransAgents() async {
    if (!state.isVoitransConfigured) {
      throw Exception('请先填写 VoiTrans 平台配置');
    }

    final client = VoitransApiClient(
      baseUrl: state.voitransBaseUrl,
      appId: state.voitransAppId,
      appSecret: state.voitransAppSecret,
    );

    final agents = await client.fetchAgents();
    final db = LocalDbBridge();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 获取当前所有 vendor="assistant" 的服务和 source="voitrans" 的 Agent
    final allServices = await db.getAllServiceConfigs();
    final assistantServices =
        allServices.where((s) => s.vendor == 'voitrans').toList();

    final allAgents = await db.getAllAgents();
    final remoteAgents = allAgents.where((a) {
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        return cfg['source'] == 'voitrans';
      } catch (_) {
        return false;
      }
    }).toList();

    final remoteAgentIds = <String>{}; // 平台返回的 agentId 集合
    int synced = 0;

    for (final agent in agents) {
      remoteAgentIds.add(agent.agentId);

      // 根据平台 Agent 类型决定本地服务类型和 Agent 类型
      String serviceType;
      String agentType;
      switch (agent.type) {
        case 'sts-chat':
        case 'chat':
          serviceType = 'sts';
          agentType = 'sts';
          break;
        case 'ast-translate':
          serviceType = 'ast';
          agentType = 'ast';
          break;
        default:
          continue; // 跳过不支持的类型
      }

      // ── 同步 ServiceConfigDto ──
      final existingSvc = assistantServices.where((s) {
        try {
          final cfg = jsonDecode(s.configJson) as Map<String, dynamic>;
          return cfg['agentId'] == agent.agentId;
        } catch (_) {
          return false;
        }
      }).toList();

      final svcConfigJson = jsonEncode({
        'agentId': agent.agentId,
        'baseUrl': state.voitransBaseUrl,
        'appId': state.voitransAppId,
        'appSecret': state.voitransAppSecret,
      });

      final String svcId;
      if (existingSvc.isNotEmpty) {
        svcId = existingSvc.first.id;
        await db.upsertServiceConfig(ServiceConfigDto(
          id: svcId,
          type: serviceType,
          vendor: 'voitrans',
          name: agent.name,
          configJson: svcConfigJson,
          createdAt: existingSvc.first.createdAt,
        ));
      } else {
        svcId = 'asst_svc_${agent.agentId.substring(0, 8)}_$now';
        await db.upsertServiceConfig(ServiceConfigDto(
          id: svcId,
          type: serviceType,
          vendor: 'voitrans',
          name: agent.name,
          configJson: svcConfigJson,
          createdAt: now,
        ));
      }

      // ── 同步 AgentDto ──
      final existingAgent = remoteAgents.where((a) {
        try {
          final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
          return cfg['remoteAgentId'] == agent.agentId;
        } catch (_) {
          return false;
        }
      }).toList();

      final serviceRefKey = serviceType == 'sts' ? 'stsServiceId' : 'astServiceId';
      final agentConfigMap = <String, dynamic>{
        'source': 'voitrans',
        'remoteAgentId': agent.agentId,
        serviceRefKey: svcId,
      };
      // 存储平台返回的支持语言列表
      if (agent.supportedLangs.isNotEmpty) {
        agentConfigMap['srcLangs'] = agent.supportedLangs;
        agentConfigMap['dstLangs'] = agent.supportedLangs;
      }
      final agentConfigJson = jsonEncode(agentConfigMap);

      if (existingAgent.isNotEmpty) {
        final ea = existingAgent.first;
        await db.upsertAgent(AgentDto(
          id: ea.id,
          name: agent.name,
          type: agentType,
          configJson: agentConfigJson,
          createdAt: ea.createdAt,
          updatedAt: now,
        ));
      } else {
        await db.upsertAgent(AgentDto(
          id: 'asst_${agent.agentId.substring(0, 8)}_$now',
          name: agent.name,
          type: agentType,
          configJson: agentConfigJson,
          createdAt: now,
          updatedAt: now,
        ));
      }

      synced++;
    }

    // ── 删除平台已移除的 ──
    for (final svc in assistantServices) {
      try {
        final cfg = jsonDecode(svc.configJson) as Map<String, dynamic>;
        if (!remoteAgentIds.contains(cfg['agentId'])) {
          await db.deleteServiceConfig(svc.id);
        }
      } catch (_) {
        await db.deleteServiceConfig(svc.id);
      }
    }
    for (final a in remoteAgents) {
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        if (!remoteAgentIds.contains(cfg['remoteAgentId'])) {
          await db.deleteAgent(a.id);
        }
      } catch (_) {
        await db.deleteAgent(a.id);
      }
    }

    return synced;
  }
}
