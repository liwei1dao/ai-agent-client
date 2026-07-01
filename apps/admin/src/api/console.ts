// console 后端接口封装。方法名即 POST /console/api/<method> 的 <method>。
// 后端 modules/console 实现对应 handler；契约统一为 {code,msg,data}。
import { call } from './request'
import type {
  LoginReq,
  LoginResp,
  ThirdSvcConfig,
  VoitransAgent,
  McpServer,
  GlobalConfigItem,
} from './types'

/* ---------------- 鉴权 ---------------- */
export const apiLogin = (req: LoginReq) => call<LoginResp>('login', req)
export const apiMe = () => call<{ account: string; identity: number }>('me')

/* ---------------- 服务配置 third_svc_config ---------------- */
export const apiGetSvcConfigs = () => call<ThirdSvcConfig[]>('getsvcconfigs')
export const apiAddSvcConfig = (cfg: ThirdSvcConfig) => call<void>('addsvcconfig', cfg)
export const apiUpdateSvcConfig = (cfg: ThirdSvcConfig) => call<void>('updatesvcconfig', cfg)
export const apiDelSvcConfig = (id: string) => call<void>('delsvcconfig', { id })

/* ---------------- Agent 配置 DBVoitransAgent ---------------- */
export const apiGetAgents = () => call<VoitransAgent[]>('getagents')
export const apiAddAgent = (a: VoitransAgent) => call<void>('addagent', a)
export const apiUpdateAgent = (a: VoitransAgent) => call<void>('updateagent', a)
export const apiDelAgent = (agent_id: string) => call<void>('delagent', { agent_id })

/* ---------------- MCP 配置 mcp_server ---------------- */
export const apiGetMcpServers = () => call<McpServer[]>('getmcpservers')
export const apiAddMcpServer = (s: McpServer) => call<void>('addmcpserver', s)
export const apiUpdateMcpServer = (s: McpServer) => call<void>('updatemcpserver', s)
export const apiDelMcpServer = (id: string) => call<void>('delmcpserver', { id })

/* ---------------- 全局配置 global_config ---------------- */
export const apiGetGlobalConfigs = () => call<GlobalConfigItem[]>('getglobalconfigs')
export const apiAddGlobalConfig = (c: GlobalConfigItem) => call<void>('addglobalconfig', c)
export const apiUpdateGlobalConfig = (c: GlobalConfigItem) => call<void>('updateglobalconfig', c)
export const apiDelGlobalConfig = (id: number) => call<void>('delglobalconfig', { id })
