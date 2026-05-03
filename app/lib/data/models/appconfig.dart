import 'dart:convert';

import '../../../data/models/appconfig_model.dart';

class AppConfig {
  static late UserGetAppConfigResp config;

  // 新增一个私有的静态布尔值来跟踪初始化状态
  static bool _isInitialized = false;

  /// 检查AppConfig单例是否已经被初始化
  /// 外部通过调用此方法来安全地检查状态
  static bool isInitialized() {
    return _isInitialized;
  }

  // 可选：提供初始化方法
  static void initialize(UserGetAppConfigResp resp) {
    config = resp;
    _isInitialized = true; // <-- 新增此行
  }

  //环境变量
  static String? env(String key) {
    return config.env[key];
  }

  //mcp配置
  static dynamic mcpConfig() {
    return {"mcpServers": config.mcps};
  }

  //智能体配置
  static String? agentsystemPrompt(String agentId) {
    final foundAgent = config.agents.firstWhere((agent) => agent.id == agentId);
    return foundAgent.systemPrompt;
  }

  static List<String> allproductNames() {
    List<String> names =
        config.products.map((user) => user.devicename).toList();
    return names;
  }

  static List<String> allproductUuids() {
    List<String> uuids = config.products.map((user) => user.scanuuid).toList();
    return uuids;
  }

//根据产品名称获取产品配置
  static DBProduct? getproduct(String name) {
    final foundProduct = config.products
        .firstWhere((product) => product.devicename.contains(name));
    return foundProduct;
  }
}
