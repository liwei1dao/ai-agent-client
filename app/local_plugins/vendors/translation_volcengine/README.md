# translation_volcengine

Part of the AI Agent SDK. See `local_plugins/CLAUDE.md` for architecture and constraints.

火山引擎机器翻译（`TranslateText`）厂商实现。调用火山引擎 OpenAPI 网关，使用
火山引擎签名 V4（HMAC-SHA256）鉴权。

配置字段：

| key               | 说明                          |
| ----------------- | ----------------------------- |
| `accessKeyId`     | 火山引擎 Access Key ID         |
| `secretAccessKey` | 火山引擎 Secret Access Key     |
| `region`          | 地域，默认 `cn-north-1`        |

网关常量（`open.volcengineapi.com` / service `translate` / action `TranslateText`
/ version `2020-06-01`）写死在实现内，与原生侧保持一致。
