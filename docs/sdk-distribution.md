# SDK 分发指南 (SDK Distribution)

**项目名称**：AI Agent Client
**版本**：v1.0
**日期**：2026-05-10
**适用读者**：维护本仓库 `local_plugins/` 的开发者；接入本 SDK 的下游业务方

---

## 0. 一句话概览

`local_plugins/` 下 26 个 Flutter package 通过 **melos workspace** 统一管理，发布到 **私有 unpub 服务**（本地 docker 起，生产可上内网域名）。下游业务方一行依赖即可拉到全套：

```yaml
dependencies:
  ai_agent_sdk: ^0.1.0
```

---

## 1. 包分层

| 层 | 包 | 数量 |
|---|---|---|
| **L0 接口** | `ai_plugin_interface`、`device_plugin_interface`、`local_db` | 3 |
| **L1 厂商** | `stt_*`、`tts_*`、`llm_*`、`sts_*`、`ast_*`、`translation_*`、`mcp`、`device_jieli` | 13 |
| **L2 复合编排** | `translate_server`、`assistant_server`、`device_manager` | 3 |
| **L3 容器** | `agent_chat`、`agent_sts_chat`、`agent_translate`、`agent_ast_translate`、`service_manager`、`agents_server` | 6 |
| **门面** | `ai_agent_sdk`（umbrella，re-export L0 + L2 + 部分 L3） | 1 |

发布顺序必须 **L0 → L1 → L2 → L3 → umbrella**，否则下游 `pub get` 解析不到 hosted 依赖。

详细架构与接口约束见 [`app/local_plugins/CLAUDE.md`](../app/local_plugins/CLAUDE.md)。

---

## 2. 维护方：发布流程

### 2.1 准备私服（首次或新机器）

```bash
cd /Users/liwei/work/docker/unpub
docker compose up -d --build       # 构建已 patch 的镜像（跳过 Google OAuth 校验）
curl http://localhost:4000          # 200 即就绪
```

unpub 部署细节见 [`/Users/liwei/work/docker/unpub/README.md`](../../../docker/unpub/README.md)。

### 2.2 工作区 bootstrap

```bash
cd /Users/liwei/work/flutter/ai-agent-client
dart pub get                        # 安装 melos 本身
melos bootstrap                     # 自动写 pubspec_overrides.yaml，把 26 包 path-link
```

`pubspec_overrides.yaml` 由 melos 自动生成，**已加入 `.gitignore`**，不要手动编辑也不要提交。日常开发就用 path 引用，零成本。

### 2.3 修改包代码后发新版

新增/修改 SDK 包的代码后：

1. **改版本号**：被改动的包以及所有传递依赖它的上游包 `pubspec.yaml` 的 `version:` 字段同步 bump（建议使用 `melos version --no-git-tag-version`）。
2. **重新 bootstrap**：`melos bootstrap`
3. **按层发布**：

```bash
# 顺序不能乱
melos exec --scope='ai_plugin_interface,device_plugin_interface,local_db' --order-dependents -- 'dart pub publish --force'
melos exec --scope='stt_*,tts_*,llm_*,sts_*,ast_*,translation_*,mcp,device_jieli' --order-dependents -- 'dart pub publish --force'
melos exec --scope='translate_server,assistant_server,device_manager' --order-dependents -- 'dart pub publish --force'
melos exec --scope='agent_*,agents_server,service_manager' --order-dependents -- 'dart pub publish --force'
melos exec --scope='ai_agent_sdk' -- 'dart pub publish --force'
```

每条命令对应 `melos.yaml` 的 `publish-l0` / `publish-l1` / `publish-l2` / `publish-l3` / `publish-umbrella` 脚本。

> **本地 unpub 重发同版本号**：unpub 默认拒绝。最快做法是删 mongo 元数据再重发：
> ```bash
> docker exec mongo mongosh unpub --quiet --eval 'db.packages.deleteOne({name: "<pkg>"})'
> ```

### 2.4 新增 SDK 包（vendor 或 agent）

1. 选好分组（vendor → `local_plugins/vendors/<能力>_<厂商>/`，agent 类型 → `local_plugins/agents/agent_<场景>/`，等等）。
2. `pubspec.yaml` 关键字段：
   - `publish_to: http://localhost:4000`（开发期）；生产期改内网私服域名
   - `version: 0.1.0`
   - `environment: { sdk: ^3.8.1, flutter: ">=3.3.0" }`
   - 内部依赖用 `^0.1.0` 等版本约束，**不要写 `path:`**——melos bootstrap 会自动生成 path 覆盖
3. 一并加 `LICENSE`、`README.md`、`CHANGELOG.md`（pub 强制要求 LICENSE，其他是 warning）。
4. 如果包含 `flutter.plugin.platforms`，必须显式声明 `flutter:` SDK 约束，否则 pub 会按 1.9.x 拒发。
5. 跑 `dart run tool/sdk_publish_prepare.dart` 自动检查 + 补漏（脚本内置 LICENSE 模板和上述约束修复）。
6. `melos bootstrap` → 拓扑层 publish。

### 2.5 改造工具脚本

- [`tool/sdk_publish_prepare.dart`](../tool/sdk_publish_prepare.dart)：批量把 25 个 SDK 包 `publish_to` / `path:` 依赖 / 缺失文件 / flutter SDK 约束一次性处理到位。新增包后可重跑，幂等。
- [`tool/check_pubspecs.dart`](../tool/check_pubspecs.dart)：用 `pubspec_parse` 校验所有 pubspec 是否能被 dart pub 解析（melos bootstrap 出错时第一手定位工具）。

---

## 3. 下游业务方：接入流程

### 3.1 普通接入（推荐）

```yaml
# 业务方 pubspec.yaml
dependencies:
  ai_agent_sdk: ^0.1.0
```

```bash
# .envrc 或 CI / dev shell
export PUB_HOSTED_URL=http://localhost:4000   # 或公司内网私服

flutter pub get
```

代码里：

```dart
import 'package:ai_agent_sdk/ai_agent_sdk.dart';

void demo() {
  // 接口层（来自 ai_plugin_interface / device_plugin_interface）
  LlmConfig(...);
  DeviceCapability.audioUplink;

  // 容器层
  AgentsServerBridge(...);
  TranslateServer(...);
  AssistantServer(...);
}
```

### 3.2 命名冲突注意

`SttEvent` / `LlmEvent` / `TtsEvent` 在 `ai_plugin_interface` 和 `agents_server` 中**同名但语义不同**。umbrella 默认导出 agent 级版本（带 `sessionId` / `requestId` / `kind`）。需要厂商级版本（写新厂商插件时）：

```yaml
dependencies:
  ai_plugin_interface: ^0.1.0
```

### 3.3 选择性裁剪

不想引入某些默认 vendor / agent 类型 / 设备厂商，**别用 umbrella**，按需挑包：

```yaml
dependencies:
  agents_server: ^0.1.0
  stt_azure: ^0.1.0
  llm_openai: ^0.1.0
  # 不要 sts_volcengine、ast_polychat 等
```

注意 `agents_server` 自身在 pubspec 里硬声明了一批 vendor 依赖（设计妥协），完全裁剪要先改 `agents_server/pubspec.yaml`。

### 3.4 PUB_HOSTED_URL 是怎么工作的

unpub 对**未知包**返回 302 → `https://pub.dev`。所以业务方设 `PUB_HOSTED_URL=http://localhost:4000` 后：

- 私有的 25 + 1 个包：从 unpub 直拉
- `flutter` / `cupertino_icons` / `uuid` 等公共包：unpub 302 → pub.dev → 业务方机器直接从 pub.dev 下载

业务方机器需要**同时能访问 unpub 和 pub.dev**。完全离线/纯内网场景需要把 pub.dev 的镜像也搬进 unpub（mongo 里灌包），不在本文范围。

---

## 4. 上线生产清单（本地 → 内网）

| 项 | 改动 |
|---|---|
| unpub 镜像 | 删 [`docker-compose 旁边的 Dockerfile`](../../../docker/unpub/Dockerfile) 里的 OAuth bypass 补丁，恢复 Google token 校验或换公司 SSO |
| publish_to | 全局把所有 26 个 pubspec.yaml 的 `http://localhost:4000` 替换成 `https://<内网 unpub 域名>` |
| HTTPS | 用反代（Caddy / nginx）给 unpub 加 cert——dart cli 配 token 时强制 HTTPS，HTTP 上传会 TLS 握手失败 |
| 业务方 PUB_HOSTED_URL | 同步改成内网域名 |
| `dart pub token add <内网域名>` | 业务方机器配置一次 |
| 鉴权 | 内网 SSO 或固定 token，避免任意人发布 |

---

## 5. 已知问题与排查

| 现象 | 根因 | 解法 |
|---|---|---|
| `dart pub publish` 报 `HandshakeException: Connection terminated during handshake` | unpub 容器调 `oauth2.googleapis.com` 验 token 时 TLS 失败（容器无 CA / 网络不通） | 已在 Dockerfile 里 patch 掉 token 校验；恢复线上后用真实鉴权方案 |
| 私有包发布成功但 `pub get` 找不到 | unpub mongo 写了 metadata 但 tarball 没落盘（早期版本 race） | `docker exec mongo mongosh unpub --eval 'db.packages.deleteOne({name:"<pkg>"})'` 后重发 |
| `pub publish --dry-run` 退出 65 | 有 git 未提交 / 缺 homepage 等 warning | 真发用 `--force`；CI 跑 dry-run 前先 commit + 加 `homepage:` |
| `melos bootstrap` 抛 `_WrappedYamlException` 且不告诉哪个文件 | 某个 pubspec.yaml 不符合 schema（重复 key / 字段格式错） | `dart run tool/check_pubspecs.dart` 定位 |
| `melos run <script>` 报 `StdinException` | 非 TTY 环境（CI / 后台），melos run 会 prompt 选包 | 改用 `melos exec --scope=...` 直接跑 |

---

## 6. 文件索引

| 路径 | 用途 |
|---|---|
| [`/Users/liwei/work/docker/unpub/`](../../../docker/unpub/) | unpub docker 部署（含 patch Dockerfile） |
| [`melos.yaml`](../melos.yaml) | melos workspace 配置 + L0~L3 + umbrella 发布脚本 |
| [`pubspec.yaml`](../pubspec.yaml) | workspace marker，含 melos / pubspec_parse 依赖 |
| [`tool/sdk_publish_prepare.dart`](../tool/sdk_publish_prepare.dart) | 批量改造脚本（pubspec 字段 + 必要文件） |
| [`tool/check_pubspecs.dart`](../tool/check_pubspecs.dart) | YAML schema 校验 |
| [`app/local_plugins/ai_agent_sdk/`](../app/local_plugins/ai_agent_sdk/) | umbrella 门面包源码 |
| [`app/local_plugins/CLAUDE.md`](../app/local_plugins/CLAUDE.md) | 包架构与运行时约束（接口/事件/requestId/状态机/错误码） |
