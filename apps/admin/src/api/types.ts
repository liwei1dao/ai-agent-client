// 数据模型 —— 字段对齐后端 pb（third_svc_config / DBVoitransAgent / mcp_server / global_config）。

/** 统一响应信封：code=0 成功 */
export interface ApiResult<T = unknown> {
  code: number
  msg: string
  data: T
}

/** 登录 */
export interface LoginReq {
  account: string
  password: string
}
export interface LoginResp {
  token: string
  account: string
  identity: number // 1 超管 2 管理员 3 代理商 4 运营
}

/** 服务字段（third_svc_config.fields[]） */
export interface SvcField {
  key: string
  description: string
  encrypted: boolean
  def_value: string
  sort: number
}

/** 第三方服务（third_svc_config） */
export interface ThirdSvcConfig {
  id: string
  name: string
  categories: string // 逗号分隔：1=LLM 2=STT 3=TTS 4=AST 5=STS 6=MT
  description: string
  enable: boolean
  fields: SvcField[]
  createtime?: number
  updatetime?: number
}

/** Agent 变量（variables[]） */
export interface AgentVariable {
  name: string
  type: string // string | number | bool
  required: boolean
  default_value: string
  description: string
}

/** Agent（DBVoitransAgent） */
export interface VoitransAgent {
  agent_id: string
  name: string
  type: string // agent_chat | agent_sts_chat | agent_translate | agent_ast_translate
  description: string
  avatar_url: string
  supported_languages: string[]
  variables: AgentVariable[]
  enable?: boolean
  llm_svc_id?: string
  tts_svc_id?: string
}

/** MCP 服务（mcp_server） */
export interface McpServer {
  id: string
  name: string
  transport: 'sse' | 'stdio' // 远程 SSE / 本地 stdio
  endpoint: string // sse: url; stdio: 命令
  enable: boolean
  tool_count?: number
  updatetime?: number
}

/** 全局配置项（global_config） */
export interface GlobalConfigItem {
  id?: number
  group: string
  key: string
  value: string
  type: 'string' | 'number' | 'bool'
  description: string
}

/** 服务类别枚举 */
export const SVC_CATEGORIES: Record<string, { label: string; color: string }> = {
  '1': { label: 'LLM', color: 'blue' },
  '2': { label: 'STT', color: 'green' },
  '3': { label: 'TTS', color: 'purple' },
  '4': { label: 'AST', color: 'cyan' },
  '5': { label: 'STS', color: 'geekblue' },
  '6': { label: 'MT', color: 'gold' },
}

/** Agent 类型枚举 */
export const AGENT_TYPES: Record<string, { label: string; color: string; icon: string }> = {
  agent_chat: { label: '文本对话', color: 'blue', icon: '🧑‍💼' },
  agent_sts_chat: { label: '语音对话', color: 'green', icon: '🎧' },
  agent_translate: { label: '三段式翻译', color: 'gold', icon: '🌍' },
  agent_ast_translate: { label: '端到端直译', color: 'cyan', icon: '⚡' },
}
