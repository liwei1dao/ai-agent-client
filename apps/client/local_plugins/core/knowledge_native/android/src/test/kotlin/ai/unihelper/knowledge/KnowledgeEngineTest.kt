package ai.unihelper.knowledge

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

/**
 * 端到端单测（镜像已验证的 Dart 自检 example/self_check.dart）。
 * 在你的环境跑：`./gradlew :knowledge_native:test`
 */
class KnowledgeEngineTest {
    @Test
    fun endToEnd() {
        val dir = Files.createTempDirectory("uh_kb_").toFile()
        val kb = KnowledgeEngine(dir.path)

        val bt = kb.ingestMarkdown(
            "u1", "连接蓝牙耳机",
            "# 如何连接 UniHelper 蓝牙耳机\n长按电源键三秒进入配对模式，在设备扫描界面点击连接即可。",
        )
        kb.ingestMarkdown("u1", "合同会议纪要", "# 会议纪要\n周二和张总讨论了合同条款三的付款节点，需本周确认。")
        kb.ingestMarkdown("u1", "本月消费", "# 本月财务\n餐饮支出 2300 元，购物 3200 元，已超预算。")

        // 索引已建立 + 真源落盘
        assertTrue(kb.vectorCount() >= 3)
        assertEquals(3, dir.listFiles { f -> f.name.endsWith(".md") }!!.size)

        // 混合检索：三个主题 Top1
        assertEquals(bt, kb.retrieve("蓝牙耳机怎么配对连接", userId = "u1").first().chunk.documentId)
        assertEquals("合同会议纪要", kb.retrieve("合同付款节点", userId = "u1").first().documentTitle)
        assertEquals("本月消费", kb.retrieve("餐饮花了多少钱", userId = "u1").first().documentTitle)

        // 带引用上下文
        assertTrue(kb.answerContext("蓝牙耳机怎么连", userId = "u1").contains("[1]"))

        // 用户级隔离
        assertTrue(kb.retrieve("蓝牙", userId = "u2").isEmpty())

        // 从 md 文库重建索引（派生自真源、可重建）
        assertEquals(3, kb.reindexFromVault())
        assertEquals(bt, kb.retrieve("蓝牙耳机怎么配对连接", userId = "u1").first().chunk.documentId)

        // 删除
        kb.deleteDocument(bt)
        assertFalse(kb.retrieve("蓝牙耳机怎么配对连接", userId = "u1").any { it.chunk.documentId == bt })

        dir.deleteRecursively()
    }
}
