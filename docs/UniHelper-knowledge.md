# UniHelper 本地用户级知识库设计

**项目名称**：UniHelper
**文档定位**：本地、用户级知识库（KB）的方案设计——落在「服务为骨」分层里，作为一个**业务服务**，建在框架层的向量/嵌入基础设施上，全团队共享。是 [UniHelper.md](UniHelper.md) 支柱③（知识库/文档问答）的展开。
**版本**：v0.1（方案稿）
**日期**：2026-07-01
**状态**：方案稿（含待定决策，见 §12）

---

## 0. 定位与原则

- **本地优先**：文档、切块、向量、索引默认全部存本地（`local_db` + 加密），可完全离线检索问答；不强制上云。
- **用户级**：知识库按**用户**隔离（personal KB）——用户自己的文档、笔记、沉淀事实、生活记录；多账户各自独立命名空间。
- **服务层自洽**：知识库是**业务服务**（Knowledge Service），检索/入库在服务层完成；设备唤醒、无 UI 场景也能查。
- **团队共享**：管家（Manager）+ 各专员都能查它（检索注入上下文），也能写它（沉淀事实）；对外还暴露为一个 MCP 工具。
- **Markdown 文库为真源**：知识库的权威存储是一个**本地 md 文件夹（vault）**，人类可读、可移植；数据库只是从 md 派生的**索引缓存**（可随时重建）。这正是"md 文档级本地个人知识库"的做法。

### 0.1 参考的本地个人知识库方案（先例）

- **Obsidian**（本地 md 库）+ 插件 *Smart Connections* / *Copilot*（本地嵌入 + 基于笔记问答，可接 Ollama 本地模型）、Web Clipper 剪藏。
- **Logseq**：本地优先大纲笔记，纯 md/org 文件落盘。
- **Khoj**：开源、可本地部署的个人 AI，索引 md/org/PDF，语义搜索 + 对话，可用本地模型离线跑——与"本地个人知识库"最贴。
- 本地嵌入式向量库：**sqlite-vec**、**LanceDB**（文件级嵌入式）、**ObjectBox**（端上 HNSW）；本地 RAG 框架 **LlamaIndex / txtai**。

> UniHelper 采同一思路：**md 文件为真源、索引本地可重建、全程端上不上云**。

---

## 1. 装什么（范围）

**已定：范围全上**（文档 + 对话沉淀 + 生活数据）。各来源统一落成/关联到 md 文库：

| 来源 | 说明 | 落到 md 文库的方式 |
|------|------|-------------------|
| **用户导入的文档** | PDF / Word / TXT / Markdown / 网页 / 图片(OCR) | 抽取正文 → 转 `.md`（图片走 OCR/Vision） |
| **笔记 / 速记** | App 或对话里记的内容 | 直接 `.md` |
| **对话沉淀** | 从聊天自动抽取"值得记住的事实/偏好" | 写成**日记 md / 事实 md**（同时进 `memories`） |
| **生活数据** | 日程/财务/健康结构化记录 | 结构化留 DB + 生成**摘要 md** / 直接语义索引（"我上月餐饮花了多少"可问答） |
| **网页剪藏 / 分享入** | 系统分享菜单 → 存入 | 抽正文 → `.md` |

> **知识库 ⊇ 长期记忆**：`memories`（画像/偏好/事实）是"高置信、结构化"的一小撮，文档/笔记是"大块非结构化"部分，两者统一检索。
> **落地节奏**：文档/笔记先跑通（M1-M2），对话沉淀（M3）与生活数据索引（M4）随后接入——范围是全的，只是分期上线。

---

## 2. 架构落位（服务为骨）

```
🏢 大楼 Flutter：我的→知识库(列表/导入/搜索) · 聊天里"喂文件即入库" · 问答命中来源可点
════════════════ 底座 ════════════════
🧱 业务服务层：Knowledge Service（知识服务）
     · ingest(source)      入库编排（解析→切块→嵌入→存）
     · retrieve(query,k)   混合检索 → 带引用的片段
     · answer(query)       RAG 组织答案（可交给管家统一发声）
     · 对管家/专员暴露 retrieve()；对 LLM 暴露为 MCP 工具 kb.search
🏗️ 框架层基础设施（可复用，尽量少改）：
     · VectorStore（向量存取 + ANN/暴力余弦）
     · EmbeddingRuntime（本地模型 / 云 Provider，可插拔）
     · local_db（documents/doc_chunks/embeddings + FTS5 关键词索引）
     · Parser/OCR（PDF/网页/图片 → 文本，复用多模态 Vision/OCR Provider）
```

- **框架层**给"通用能力"：向量存取、嵌入运行时、全文索引、解析——**可复用、稳定**。
- **业务服务层**给"知识逻辑"：入库策略、检索融合、RAG 答案组织、什么该自动沉淀。
- 这样别的业务服务（日程/邮件…）也能直接调 `KnowledgeService.retrieve()` 拿用户上下文。

---

## 3. 数据流水线

```
入库 ingest：
  源(文档/笔记/图片/网页)
    → 解析 Parse（PDF/网页抽正文；图片走 OCR/Vision → 文本）
      → 切块 Chunk（按语义/长度，重叠窗口；记 source/位置用于溯源）
        → 嵌入 Embed（EmbeddingRuntime）
          → 存储 Store（doc_chunks + embeddings 向量 + FTS5 关键词）

检索 retrieve：
  query
    → 向量检索（KNN）  ┐
    → 关键词检索(FTS5) ┘→ 融合(RRF) → (可选)重排 rerank → topK 片段(带引用)
      → 注入 LLM 上下文 → 生成答案 + 引用溯源
```

---

## 4. 存储方案（md 文库为真源 + 本地派生索引）

**真源 = Markdown 文库**：权威存储是一个**本地 md 文件夹（vault）**——每条笔记/导入文档一份 `.md`，附件同目录。人类可读、可移植、任意编辑器可改、可 git/网盘同步、**删了 DB 也不丢**。桌面端可直接指向已有 Obsidian/Logseq 库。

**派生 = 本地索引（可随时重建）**：在 `local_db`（SQLite）建**索引缓存**——`documents/doc_chunks`（切块 + 溯源位置）、`doc_chunks_fts`（FTS5 关键词，中文可配分词）、`embeddings`（向量）。索引从 md 派生，删了能重建、换模型能重嵌。

- **向量检索**：`embeddings.vector` + **`sqlite-vec`**（或个人规模直接**暴力余弦**，< 10 万切块足够快）；一个库、零外依赖、事务一致 → **MVP 首选**。
- **规模化**：切块量/延迟超阈值再迁 **LanceDB / ObjectBox HNSW**；因真源是 md，索引迁移**无损重建**。
- **加密 at rest**：md 真源与索引同级保护（SQLCipher / 钥匙串密钥）；文件级可选加密。

> 精髓：**真源是可读文件、DB 只是缓存**——最稳、最本地、最可迁移。

---

## 5. 嵌入方案（EmbeddingRuntime，端上为准）

**已定：嵌入全程在端上算，不上云。** 用端上小模型跑 ONNX——中文 `bge-small-zh-v1.5` / 多语 `multilingual-e5-small`（约 100~130MB，384 维）。文本**不出设备**，可离线、可被设备唤醒场景直接用。

- **接口化**：走 `EmbeddingProvider`（UniHelper.md §5.3），维度/模型名随向量记录（`embeddings.model/dim`），换模型可后台重嵌（真源是 md，重嵌无损）。
- **云嵌入**仅作"高级可选"（**默认关闭**）：个别用户想要更高质量且接受联网时才开；默认体验**全程本地**。
- 同一 KB 不混用两种模型（混用需重嵌）。

---

## 6. 检索与问答

- **混合检索**：向量（语义）+ FTS5（关键词/专名）→ **RRF** 融合，兼顾"意思相近"和"精确命中"。
- **重排（可选）**：小 rerank 模型或 LLM 打分，topN→topK。
- **RAG 生成**：topK 片段拼进提示，LLM 生成**带引用**答案（引用可点回原文位置）。
- **溯源**：每条片段带 `document_id + 位置`，UI 上"来源"可点开原文。

---

## 7. 与团队 / 唤醒集成

- **管家注入**：每轮对话前，Manager 用 query 检索 KB + memories，放进 `TaskContext.memories/blackboard`，专员即拿到用户上下文（避免重复问）。
- **专员直查**：如"日程服务"排会时查用户偏好（"我一般不排早上的会"）；"邮件服务"起草时引用 KB 里的签名/常用措辞。
- **MCP 工具**：对 LLM 暴露 `kb.search(query)`，让模型自行按需检索。
- **设备唤醒场景**：KB 检索在**服务层**完成，设备唤醒问答（"我上次记的那个 Wi-Fi 密码是啥"）无需开 App 也能查并 TTS 播报（受隐私策略约束，敏感项可要求本机在手/语音确认）。

### 7.1 集成落点：`KnowledgeBusinessService`（已随 knowledge_native 提供）

原生引擎已封好业务服务面（`knowledge_native` 的 `service/KnowledgeBusinessService.kt` / `.swift`），agents_server 按其 Manager/MCP 接口适配两处即可：

```
agents_server（纯原生）
├─ 管家(Manager) 每轮对话前：
│    val ctx = svc.contextFor(userText, userId)     // 带引用的 RAG 上下文
│    systemPrompt = base + (ctx ?? "")              // 注入 → 专员/LLM 拿到用户知识
└─ LLM 工具表注册：
     registerTool(svc.toolDescriptor())             // MCP 工具 kb.search 的 JSON 描述
       onCall = { args -> svc.invokeTool(args, userId) }   // 模型自检索 → 返回带来源片段
```

- `contextFor()`：主动注入（管家路由前先喂知识），零往返。
- `kb.search`（`toolDescriptor()`+`invokeTool()`）：被动按需（模型判断要查时自己调）。两者互补。
- 只依赖引擎 + 平台内置 JSON，不感知 agents_server 具体类型；协议对齐见 [UniHelper-agents-protocol.md](UniHelper-agents-protocol.md)（§0.2 业务服务、§5 SpecialistAgent）。

---

## 8. UI（落在现有 4-Tab）

- **我的 → 知识库**：文档/笔记列表、导入入口（文件/网页/拍照 OCR）、搜索、来源管理、嵌入设置（本地/云）、占用与清理。
- **聊天里喂料**：输入栏 📎 附件选"存入知识库"；或直接发文件 → 助手问"要我记进知识库吗？"。
- **自然语言问答**：用户在聊天直接问，命中 KB 时答案带"来源"卡片，可点开原文。
- **系统分享入**：分享菜单 → UniHelper → 存入 KB。

---

## 9. 数据模型增量

对齐 [UniHelper-app-design.md](UniHelper-app-design.md) §9 的 `documents/doc_chunks/embeddings`，补充来源与命名空间：

```sql
-- 知识源（一次导入 = 一个 source）
CREATE TABLE kb_sources (
  id TEXT PRIMARY KEY, user_id TEXT, kind TEXT,      -- file|note|web|chat|life
  title TEXT, uri TEXT, mime TEXT, status TEXT,       -- importing|ready|failed
  created_at INTEGER
);
-- 文档（解析后的逻辑文档，可多份来自一个 source）
CREATE TABLE documents (
  id TEXT PRIMARY KEY, source_id TEXT, user_id TEXT,
  title TEXT, meta_json TEXT, created_at INTEGER
);
-- 切块
CREATE TABLE doc_chunks (
  id TEXT PRIMARY KEY, document_id TEXT, ordinal INTEGER,
  text TEXT, loc_json TEXT                             -- 页码/字符区间，用于溯源
);
CREATE VIRTUAL TABLE doc_chunks_fts USING fts5(text, content='doc_chunks');  -- 关键词
-- 向量
CREATE TABLE embeddings (
  chunk_id TEXT PRIMARY KEY, dim INTEGER, model TEXT, vector BLOB
);
-- memories（长期记忆）与 KB 统一检索；见 app-design §9
```

> 全部带 `user_id` 做**用户级隔离**；`vector` 为二进制向量；换模型时按 `model` 增量重嵌。

---

## 10. 隐私与同步

- **默认本地 + 加密**：不上云也完整可用。
- **可选端到端加密同步/备份**：走后端仅存密文（密钥不出端），或用户自选网盘；同步冲突以 source 粒度合并。
- **敏感项策略**：标记敏感的知识（密码/证件）在无 UI 唤醒场景下要求本机在手 / 语音确认才读出。

---

## 11. 分期落地

| 阶段 | 内容 |
|------|------|
| **M1** | 文件/笔记导入 + 本地嵌入 + (暴力余弦 或 sqlite-vec) + FTS5 + 聊天问答带引用 |
| **M2** | 图片 OCR/Vision 入库 + 网页/分享入 + 来源管理 UI |
| **M3** | 对话自动沉淀（→ memories）+ 管家/专员检索注入 |
| **M4** | 规模化（ObjectBox HNSW 可选）+ 重排 + 生活数据语义索引 |
| **M5** | 端到端加密同步 |

---

## 12. 决策（已定）

- **A. 嵌入 = 端上本地模型（不上云）** ✅ ONNX `bge-small-zh` / `e5-small`；云嵌入仅高级可选、默认关。
- **B. 存储 = md 文库为真源 + SQLite 派生索引（sqlite-vec + FTS5，MVP）** ✅ 规模大再迁 LanceDB / ObjectBox HNSW（真源是 md，迁移无损）。
- **C. 入库范围 = 全上** ✅ 文档 + 对话沉淀（→ md 日记/事实笔记）+ 生活数据（结构化 DB + md 摘要/语义索引）；文档/笔记先跑通，对话/生活随 M3/M4 接入。
