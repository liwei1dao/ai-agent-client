# ai_plugin_interface

AI agent SDK 的接口契约层：定义 STT / TTS / LLM / STS / AST / Translation / MCP 各能力的抽象类、配置、事件结构。所有厂商实现 (`stt_*`, `tts_*`, `llm_*`, `sts_*`, `ast_*`, `translation_*`) 必须依赖本包；上层调度（`agent_*`、`agents_server`、`service_manager`）通过本包定义的抽象类与厂商解耦。

> 内部 SDK 包，不公开发布。详细约束见仓库 `local_plugins/CLAUDE.md`。
