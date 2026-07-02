/// UniHelper 多 Agent 团队编排内核（core/agent_kernel）。
///
/// 对外一个 [Manager]（管家，单一发声）+ 对内一支 [SpecialistAgent]（专员）团队。
/// 见 docs/UniHelper-agents-protocol.md。纯 Dart：算法规范 + web/桌面运行时；
/// 移动端 agents_server（纯原生）按此镜像。
library;

export 'src/models.dart';
export 'src/ports.dart';
export 'src/rule_router.dart';
export 'src/adapter.dart';
export 'src/manager.dart';
