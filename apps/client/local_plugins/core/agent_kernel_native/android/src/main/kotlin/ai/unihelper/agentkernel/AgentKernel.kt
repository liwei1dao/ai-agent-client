package ai.unihelper.agentkernel

/**
 * 多 Agent 团队编排内核（Kotlin）——镜像已跑绿的纯 Dart `core/agent_kernel`。
 *
 * 供纯原生 agents_server 直接使用：[Manager] 单一发声 + 路由 + [SpecialistAgent] 团队 + [WakeBus]。
 * 骨架用同步 `List<AgentEvent>`（流式后续可换 Flow/回调）。见 docs/UniHelper-agents-protocol.md。
 */

typealias AgentId = String

enum class AgentStatus { OK, PARTIAL, REJECTED, FAILED }

data class AgentCapability(
    val id: AgentId,
    val name: String,
    val keywords: List<String> = emptyList(),
    val description: String = "",
    val triggers: List<String> = emptyList(),
)

data class TaskEnvelope(
    val taskId: String,
    val requestId: String,
    val from: AgentId,
    val to: AgentId,
    val intent: String,
    val text: String,
    val params: Map<String, Any?> = emptyMap(),
    val context: String? = null,
    val userId: String? = null,
    val needConfirm: Boolean = false,
)

sealed class AgentEvent
data class AgentPartial(val text: String) : AgentEvent()
data class AgentProgress(val note: String) : AgentEvent()
data class AgentResult(
    val text: String,
    val status: AgentStatus = AgentStatus.OK,
    val data: Map<String, Any?> = emptyMap(),
    val citations: List<Citation> = emptyList(),
) : AgentEvent()
data class AgentNeedConfirm(val confirm: Confirm) : AgentEvent()
data class AgentError(val code: String, val message: String) : AgentEvent()

data class Citation(val title: String, val ref: String? = null)
data class Confirm(
    val id: String,
    val actionKind: String,
    val summary: String,
    val preview: Map<String, Any?> = emptyMap(),
    val editable: Boolean = true,
)

data class ManagerReply(
    val text: String,
    val usedAgents: List<AgentId> = emptyList(),
    val citations: List<Citation> = emptyList(),
    val pendingConfirm: Confirm? = null,
) {
    val needsConfirm: Boolean get() = pendingConfirm != null
}

enum class WakeSource { DEVICE, HOTWORD, SCHEDULE, INCOMING_CALL, GEOFENCE, PUSH }
data class WakeEvent(
    val source: WakeSource,
    val sourceId: String,
    val utterance: String? = null,
    val payload: Map<String, Any?> = emptyMap(),
)
data class TriggerContext(val kind: String, val source: String, val params: Map<String, Any?> = emptyMap())

interface SpecialistAgent {
    val capability: AgentCapability
    fun handle(task: TaskEnvelope): List<AgentEvent>
    fun onTrigger(ctx: TriggerContext): List<AgentEvent> = emptyList()
}

interface ContextProvider {
    fun contextFor(query: String, userId: String? = null): String?
}

interface Router {
    fun route(text: String, caps: List<AgentCapability>, userId: String? = null): List<AgentId>
}

interface LlmRouter {
    fun pick(text: String, caps: List<AgentCapability>): AgentId?
}

/** 关键词命中 → 候选；未命中 → LLM 兜底 → fallback（默认对话）。 */
class RuleRouter(private val fallback: AgentId = "chat", private val llm: LlmRouter? = null) : Router {
    override fun route(text: String, caps: List<AgentCapability>, userId: String?): List<AgentId> {
        val lower = text.lowercase()
        val matched = caps.filter { c -> c.keywords.any { lower.contains(it.lowercase()) } }.map { it.id }
        if (matched.isNotEmpty()) return matched
        llm?.pick(text, caps)?.let { return listOf(it) }
        return listOf(fallback)
    }
}

/** 管家：单一外部面孔——路由 → 分派(可多专员) → 汇总一个声音 + 上下文注入 + 确认闸口 + 唤醒。 */
class Manager(
    private val router: Router,
    private val contextProvider: ContextProvider? = null,
) {
    private val agents = LinkedHashMap<AgentId, SpecialistAgent>()
    private var seq = 0
    private fun id(p: String) = "$p-${seq++}"

    fun register(a: SpecialistAgent) { agents[a.capability.id] = a }
    val capabilities: List<AgentCapability> get() = agents.values.map { it.capability }

    fun handle(userText: String, userId: String? = null): ManagerReply {
        val requestId = id("req")
        val context = contextProvider?.contextFor(userText, userId)
        val ids = router.route(userText, capabilities, userId)
        val used = ArrayList<AgentId>()
        val citations = ArrayList<Citation>()
        val buf = StringBuilder()
        var pending: Confirm? = null
        for (aid in ids) {
            val agent = agents[aid] ?: continue
            used.add(aid)
            val task = TaskEnvelope(
                id("task"), requestId, "manager", aid, agent.capability.id, userText,
                context = context, userId = userId,
            )
            for (e in agent.handle(task)) {
                when (e) {
                    is AgentResult -> {
                        if (buf.isNotEmpty()) buf.append('\n')
                        buf.append(e.text); citations.addAll(e.citations)
                    }
                    is AgentNeedConfirm -> pending = e.confirm
                    is AgentError -> {
                        if (buf.isNotEmpty()) buf.append('\n')
                        buf.append("（$aid 出错：${e.message}）")
                    }
                    is AgentPartial, is AgentProgress -> {}
                }
            }
        }
        return ManagerReply(buf.toString(), used, citations, pending)
    }

    /** 服务级唤醒入口（被 WakeBus 调起，可能无 Flutter 在场）。 */
    fun onWake(e: WakeEvent): ManagerReply? {
        val text = e.utterance
        if (text.isNullOrEmpty()) return null
        return handle(text, e.payload["userId"] as? String)
    }
}

/** 框架层唤醒总线：各唤醒源统一 emit，路由到管家/专员。 */
class WakeBus {
    private val handlers = ArrayList<(WakeEvent) -> Unit>()
    fun on(h: (WakeEvent) -> Unit) { handlers.add(h) }
    fun emit(e: WakeEvent) { for (h in handlers) h(e) }
}
