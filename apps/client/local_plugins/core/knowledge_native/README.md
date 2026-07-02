# knowledge_native — 知识库原生引擎（Kotlin / Swift）

`local_plugins/core/knowledge_native` · Flutter 插件（Android Kotlin ✅ / iOS Swift ✅）

移动端 `agents_server` 是**纯 Kotlin/Swift 原生**，需在**后台 / 设备唤醒 / App 被杀**时直接查知识库（不经 Flutter）。本插件即那份**原生引擎**——逻辑忠实移植已验证的纯 Dart 包 [`knowledge`](../knowledge/)（算法规范 + web/桌面运行时）。

## 谁调它

```
移动端（Android/iOS）
  agents_server（纯原生）── 直接 new ──► KnowledgeEngine（Kotlin/Swift）   ← 主用户，后台/唤醒可用
  Flutter「我的→知识库」UI ── MethodChannel ──► KnowledgePlugin ─► KnowledgeEngine

web / 桌面
  agents_server（Dart 运行时）──► 纯 Dart 包 knowledge 的 KnowledgeService
```

> 同一套算法两份实现，是"移动端原生 / web·桌面 Dart"架构的必然；Dart 包是**算法规范与 web·桌面实现**，Kotlin/Swift 是**移动端实现**，两者行为对齐（见各自端到端测试）。

## agents_server 直接用（后台/唤醒，不经 Flutter）

```kotlin
val kb = KnowledgeEngine(File(context.filesDir, "kb_vault").path)
kb.ingestMarkdown("u1", "连接蓝牙耳机", "…")          // 写 md 文库(真源) + 建索引
val ctx = kb.answerContext("蓝牙耳机怎么配对", userId = "u1")  // → 交 LLM 生成答案
```

## 结构

```
android/src/main/kotlin/ai/unihelper/knowledge/
├── KnowledgeCore.kt     分词/FNV-1a · 模型 · 端口(EmbeddingProvider/VectorStore/KnowledgeStore)
│                        · HashingEmbedding(默认/离线) · Chunker · 内存存储 · Retriever(向量+关键词RRF)
├── KnowledgeEngine.kt   MarkdownVault(真源落盘) + 门面(ingest/retrieve/answerContext/delete/reindex)
└── KnowledgePlugin.kt   Flutter UI 桥（手动 MethodChannel）
android/src/test/kotlin/... KnowledgeEngineTest.kt   端到端测试（镜像 Dart 自检）
ios/Classes/
├── KnowledgeCore.swift      镜像 KnowledgeCore.kt
├── KnowledgeEngine.swift    镜像 KnowledgeEngine.kt
└── KnowledgePlugin.swift    Flutter UI 桥（FlutterMethodChannel）
ios/knowledge_native.podspec
lib/knowledge_native.dart   Flutter UI 侧 Dart 门面
```

## 端口实现（已随包提供，注入即用）

引擎构造函数支持注入端口，业务不变：

```kotlin
// Android：真·SQLite 索引（内置库，无需外部依赖）
val idx = SqliteKnowledgeIndex(context)                       // ai.unihelper.knowledge.sqlite
val kb = KnowledgeEngine(
    vaultPath,
    store = idx.store, vectors = idx.vectors,                 // ✅ 真索引（默认是内存）
    // embedder = OnnxEmbedding(modelPath)                    // ⏳ 端上嵌入（脚手架，接模型后启用）
)
```
```swift
// iOS：真·SQLite 索引（系统 SQLite3）
let idx = SqliteKnowledgeIndex(path: dbPath)
let kb = KnowledgeEngine(vaultPath: vaultPath, store: idx.store, vectors: idx.vectors
                         /*, embedder: OnnxEmbedding(modelPath: m) */)
```

| 端口 | 默认（随包，可跑） | 生产实现（随包） |
|------|------------------|-----------------|
| `VectorStore`+`KnowledgeStore` | 内存（InMemory*） | **✅ SQLite**：`sqlite/SqliteStores.kt`（Android 内置）、`SqliteStores.swift`（iOS SQLite3）——BLOB 向量 + 暴力余弦，个人 KB 规模无需 sqlite-vec |
| `EmbeddingProvider` | `HashingEmbedding`（离线可跑） | **🟡 ONNX（分词+池化已就位）**：`WordPieceTokenizer` + `OnnxEmbedding`（真实逻辑，含 masked mean-pool + L2 归一）；只差实现 `OnnxSession`(ORT 前向) + 提供模型/vocab，见「ONNX 接入」 |

## ONNX 接入（把默认哈希嵌入换成真语义嵌入）

`WordPieceTokenizer`（BERT 分词）+ `OnnxEmbedding`（分词→masked mean-pool→L2 归一）**已写全、可单测**（`OnnxEmbeddingTest.kt`）。只需在你的环境补两样：**模型/vocab 资源** + **`OnnxSession`（ORT 前向）实现**。

1) 依赖：Android `implementation("com.microsoft.onnxruntime:onnxruntime-android:1.17.+")`；iOS `pod 'onnxruntime-objc'`
2) 资源：把 `bge-small-zh-v1.5.onnx` + `vocab.txt` 打包进 assets/bundle（或下载到 filesDir/Documents）
3) 实现 `OnnxSession`（Android 示例；iOS 用 onnxruntime-objc 同理）：
```kotlin
class OrtSession(modelPath: String) : OnnxSession {
    private val env = OrtEnvironment.getEnvironment()
    private val sess = env.createSession(modelPath)
    override fun run(ids: LongArray, mask: LongArray): Array<FloatArray> {
        val shape = longArrayOf(1, ids.size.toLong())
        val inputs = mapOf(
            "input_ids" to OnnxTensor.createTensor(env, arrayOf(ids), shape),       // 输入名以模型为准
            "attention_mask" to OnnxTensor.createTensor(env, arrayOf(mask), shape),
        )
        sess.run(inputs).use { return (it[0].value as Array<Array<FloatArray>>)[0] }
    }
}
```
4) 注入引擎：
```kotlin
val vocab = WordPieceTokenizer.fromVocabText(assets.open("vocab.txt").bufferedReader().readText())
val emb = OnnxEmbedding(WordPieceTokenizer(vocab), OrtSession(modelPath))
val kb = KnowledgeEngine(vaultPath, embedder = emb, store = idx.store, vectors = idx.vectors)
```
> 换模型需重嵌：`KnowledgeEngine.reindexFromVault()`（真源是 md，重嵌无损）。

## agents_server 集成（KnowledgeBusinessService）

`service/KnowledgeBusinessService.{kt,swift}` 已封好两个集成面，agents_server 适配即可：

```kotlin
val svc = KnowledgeBusinessService(kb)
// 管家每轮对话前注入 RAG 上下文：
val sys = base + (svc.contextFor(userText, userId) ?: "")
// LLM 工具表注册 MCP 工具 kb.search：
registerTool(svc.toolDescriptor()) { args -> svc.invokeTool(args, userId) }
```

- `contextFor()` = 主动注入（零往返）；`kb.search` = 被动按需（模型自检索）。互补。
- 详见 `docs/UniHelper-knowledge.md` §7.1 与 `docs/UniHelper-agents-protocol.md`。

## 待办

- ✅ SQLite 真索引（Android/iOS）· ✅ ONNX 端上嵌入脚手架 · ✅ agents_server 集成面（KnowledgeBusinessService）
- ⏳ ONNX 接模型+分词跑通（脚手架已就位）；可选 FTS/HNSW/sqlite-vec 优化
- ⏳ 在真实 agents_server 里落地 `contextFor`/`kb.search` 的适配与用户级 userId 传递

## ⚠️ 验证状态

Kotlin 与 Swift 均逐行对照**已跑绿的 Dart 核心**移植；但本工作副本无 Android/Xcode 工具链、无 monorepo 其余源码，**未做编译级验证**。请在你的真实环境验证：Android `./gradlew :knowledge_native:test` 跑 `KnowledgeEngineTest`（gradle/AGP/JDK 按项目对齐，memory 记录构建需 JDK21）；iOS 用 XCTest 按同用例验证 `KnowledgeEngine`。Kotlin 包名 `ai.unihelper.knowledge` 为占位，需对齐真实 applicationId。
