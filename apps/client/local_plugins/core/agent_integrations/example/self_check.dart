// 连接中心自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_integrations/agent_integrations.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final store = InMemoryConnectionStore();
  final vault = InMemoryCredentialVault();
  final reg = IntegrationRegistry(store: store, vault: vault);

  stdout.writeln('▶ 目录 / 初始状态');
  check(reg.list().length == 6, '默认目录 6 个（邮箱/钉钉/企业微信/飞书/系统日历/Google）');
  check(reg.list().every((c) => c.status == ConnStatus.disconnected), '初始全部未连接');
  check(reg.feeding(Feed.mail).isEmpty, '无已连接 → feeding(mail) 空');

  stdout.writeln('▶ 授权邮箱（IMAP）→ 凭据入保险箱');
  final c = await reg.connect('email', AuthPayload.imap('imap.corp.com', 'zhang@corp.com', 'app-pass-123'));
  check(c.status == ConnStatus.connected && c.account == 'zhang@corp.com', '邮箱已连接、账号记录');
  check(c.credRef != null, '生成 credRef（凭据引用）');
  final cred = await reg.credentialsOf('email');
  check(cred?['appPassword'] == 'app-pass-123', '凭据可从保险箱取回（供业务服务构建 MailProvider）');

  stdout.writeln('▶ feeding：业务服务据此找数据源');
  check(reg.feeding(Feed.mail).map((e) => e.id).contains('email'), 'feeding(mail) → email（喂给 EmailService.MailProvider）');

  stdout.writeln('▶ 持久化 / 跨会话恢复');
  final reg2 = IntegrationRegistry(store: store, vault: vault);
  await reg2.restore();
  check(reg2.get('email')!.status == ConnStatus.connected, '新会话 restore 后邮箱仍连接');

  stdout.writeln('▶ 动态加 MCP 连接器（联网/通用工具）');
  reg.addConnector(Connector(id: 'mcp:notion', name: 'Notion MCP', authType: AuthType.mcp, feeds: {Feed.tool, Feed.docs}));
  await reg.connect('mcp:notion', AuthPayload.mcp('https://mcp.notion.example', name: 'Notion'));
  check(reg.feeding(Feed.tool).map((e) => e.id).contains('mcp:notion'), 'MCP 连接器 → feeding(tool)（对 LLM 暴露工具）');

  stdout.writeln('▶ 断开 → 回收凭据');
  await reg.disconnect('email');
  check(reg.get('email')!.status == ConnStatus.disconnected, '邮箱已断开');
  check(await reg.credentialsOf('email') == null, '断开后凭据被回收');
  check(reg.feeding(Feed.mail).isEmpty, 'feeding(mail) 又为空');

  stdout.writeln('\n✅ 连接中心通过：目录 · 授权 · 凭据保险箱 · feeding 喂业务 · 持久化恢复 · 动态MCP · 断开回收。');
}
