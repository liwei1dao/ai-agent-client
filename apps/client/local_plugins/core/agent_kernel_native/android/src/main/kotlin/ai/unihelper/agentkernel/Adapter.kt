package ai.unihelper.agentkernel

/**
 * 把"现有 agent"（对话/翻译/…）包成管家可调度的 [SpecialistAgent]，**不改其基础模板/NativeAgent 契约**。
 * 镜像 Dart agent_kernel/adapter.dart。骨架用同步 List（流式后续换 Flow/回调）。
 */

enum class RunnerSignal { FIRST_TOKEN, CHUNK, TOOL_CALL_START, TOOL_CALL_RESULT, DONE, ERROR, NEED_CONFIRM }

data class RunnerEvent(
    val signal: RunnerSignal,
    val text: String? = null,
    val toolName: String? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
    val confirm: Confirm? = null,
) {
    companion object {
        fun chunk(t: String) = RunnerEvent(RunnerSignal.CHUNK, text = t)
        fun done(t: String? = null) = RunnerEvent(RunnerSignal.DONE, text = t)
        fun error(code: String, msg: String) = RunnerEvent(RunnerSignal.ERROR, errorCode = code, errorMessage = msg)
        fun tool(name: String) = RunnerEvent(RunnerSignal.TOOL_CALL_START, toolName = name)
        fun confirmNeeded(c: Confirm) = RunnerEvent(RunnerSignal.NEED_CONFIRM, confirm = c)
    }
}

/**
 * 把一次请求的运行规约为 [RunnerEvent]。由 app 用**现有 agent 的既有接口**实现
 * （如 startSession/sendText + onLlmChunk/onLlmDone… → RunnerEvent），不改基础模板。
 */
interface LegacyAgentRunner {
    fun run(text: String, context: String? = null, userId: String? = null): List<RunnerEvent>
}

/** 通用适配器：流式 chunk → 汇总 [AgentResult]；工具→进度；错误→[AgentError]；确认→[AgentNeedConfirm]。 */
class SpecialistAdapter(
    override val capability: AgentCapability,
    private val runner: LegacyAgentRunner,
) : SpecialistAgent {
    override fun handle(task: TaskEnvelope): List<AgentEvent> {
        val out = ArrayList<AgentEvent>()
        val buf = StringBuilder()
        for (e in runner.run(task.text, task.context, task.userId)) {
            when (e.signal) {
                RunnerSignal.FIRST_TOKEN, RunnerSignal.TOOL_CALL_RESULT -> {}
                RunnerSignal.CHUNK -> e.text?.let { buf.append(it); out.add(AgentPartial(it)) }
                RunnerSignal.TOOL_CALL_START -> out.add(AgentProgress("调用工具：${e.toolName ?: ""}"))
                RunnerSignal.NEED_CONFIRM -> e.confirm?.let { out.add(AgentNeedConfirm(it)) }
                RunnerSignal.DONE -> out.add(AgentResult(if (!e.text.isNullOrEmpty()) e.text else buf.toString()))
                RunnerSignal.ERROR -> out.add(AgentError(e.errorCode ?: "error", e.errorMessage ?: "未知错误"))
            }
        }
        return out
    }
}
