/// UniHelper 第三方连接与授权中心（core/agent_integrations）。
///
/// 统一授权邮件/钉钉/企业微信/飞书/日历/MCP…；连接后经 [IntegrationRegistry.feeding]
/// 把数据源喂给业务服务端口（如邮箱→MailProvider、日历→ScheduleService）。
/// 见 docs/UniHelper-integrations-persistence.md。
library;

export 'src/models.dart';
export 'src/ports.dart';
export 'src/registry.dart';
