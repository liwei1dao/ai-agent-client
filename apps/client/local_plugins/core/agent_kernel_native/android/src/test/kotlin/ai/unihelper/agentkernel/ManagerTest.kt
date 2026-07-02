package ai.unihelper.agentkernel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** 端到端单测（镜像 Dart agent_kernel/self_check）。`./gradlew :agent_kernel_native:test` */
class ManagerTest {
    private fun mgr(): Manager {
        val m = Manager(RuleRouter(), object : ContextProvider {
            override fun contextFor(query: String, userId: String?): String? =
                if (query.contains("密码") || query.contains("路由器")) "管理密码 admin8899" else null
        })
        m.register(object : SpecialistAgent {
            override val capability = AgentCapability("chat", "对话", listOf("聊", "你好", "介绍"))
            override fun handle(task: TaskEnvelope) =
                listOf(AgentResult("好的，我在。" + if (task.context != null) "（据知识库：${task.context}）" else ""))
        })
        m.register(object : SpecialistAgent {
            override val capability = AgentCapability("translate", "翻译", listOf("翻译", "translate"))
            override fun handle(task: TaskEnvelope) = listOf(AgentResult("translated: hello world"))
        })
        m.register(object : SpecialistAgent {
            override val capability = AgentCapability("email", "邮件", listOf("邮件", "回复"))
            override fun handle(task: TaskEnvelope) =
                listOf(AgentProgress("起草中…"), AgentNeedConfirm(Confirm("c1", "send_email", "给张总回复：同意")))
        })
        m.register(object : SpecialistAgent {
            override val capability = AgentCapability("schedule", "日程", listOf("日程", "提醒", "会", "安排"), triggers = listOf("device"))
            override fun handle(task: TaskEnvelope) = listOf(AgentResult("已创建日程：${task.text}"))
        })
        return m
    }

    @Test
    fun routing() {
        val m = mgr()
        assertTrue(m.handle("帮我翻译 hello").usedAgents.contains("translate"))
        assertEquals(listOf("chat"), m.handle("随便聊两句").usedAgents)
        assertEquals(listOf("chat"), m.handle("讲个笑话呗").usedAgents)
    }

    @Test
    fun confirmGate() {
        val r = mgr().handle("给张总回复邮件说同意")
        assertTrue(r.needsConfirm)
        assertEquals("send_email", r.pendingConfirm!!.actionKind)
    }

    @Test
    fun contextInjection() {
        assertTrue(mgr().handle("我家路由器密码是多少").text.contains("admin8899"))
    }

    @Test
    fun wake() {
        val m = mgr()
        var woke: ManagerReply? = null
        val bus = WakeBus()
        bus.on { woke = m.onWake(it) }
        bus.emit(WakeEvent(WakeSource.DEVICE, "buds-01", "加个明早十点的会"))
        assertTrue(woke!!.usedAgents.contains("schedule"))
    }

    @Test
    fun adapterAggregation() {
        // 假"现有对话 agent"：流式 chunk（对应 onLlmChunk → onLlmDone）
        val runner = object : LegacyAgentRunner {
            override fun run(text: String, context: String?, userId: String?) =
                listOf(RunnerEvent.chunk("这是"), RunnerEvent.chunk("答案"), RunnerEvent.done())
        }
        val m = Manager(RuleRouter())
        m.register(SpecialistAdapter(AgentCapability("explain", "讲解", listOf("讲讲", "解释")), runner))
        val r = m.handle("讲讲量子力学")
        assertTrue(r.usedAgents.contains("explain"))
        assertEquals("这是答案", r.text)   // 流式 chunk 经适配器汇总
    }
}
