# AI Agent 管理后台（apps/admin）

全能助手 App 的管理后台前端。**React 18 + Vite + TypeScript + Ant Design 5**。

只做四个配置域：**服务配置 · Agent 配置 · MCP 配置 · 全局配置**（+ 登录）。

## 开发

```bash
cd apps/admin
npm install
npm run dev      # http://localhost:5180/console/
```

开发期 `/console/api` 已代理到本地 console 服务（`http://127.0.0.1:8080`，见 vite.config.ts）。
需先启动后端：`cd apps/services/services/console && go run . -conf ./conf/console.yaml`

## 构建 & 部署

```bash
npm run build    # 产物在 dist/，base=/console/
```

把 `dist/` 拷到 console 服务的 `consoleweb/` 静态目录即可被托管（console.yaml 的 `StaticDir`）。

## 目录

```
src/
  api/
    request.ts     # axios 封装：POST /console/api/<method>，JWT 头，{code,msg,data} 解包
    console.ts     # 接口方法（login / svcconfig / agents / mcp / global）
    types.ts       # 数据模型（对齐后端 third_svc_config / DBVoitransAgent / mcp_server / global_config）
  store/auth.ts    # 登录态（zustand + localStorage）
  layout/AdminLayout.tsx
  pages/
    Login.tsx
    Services.tsx       # 服务配置：表格 + Drawer 表单 + 动态 fields
    Agents.tsx         # Agent 列表（卡片）
    AgentEdit.tsx      # Agent 创建/编辑
    Mcp.tsx
    GlobalConfig.tsx
```

## 后端契约

| 页面 | 接口（POST /console/api/） |
|---|---|
| 登录 | `login` |
| 服务配置 | `getsvcconfigs` / `addsvcconfig` / `updatesvcconfig` / `delsvcconfig` |
| Agent | `getagents` / `addagent` / `updateagent` / `delagent` |
| MCP | `getmcpservers` / `addmcpserver` / `updatemcpserver` / `delmcpserver` |
| 全局配置 | `getglobalconfigs` / `addglobalconfig` / `updateglobalconfig` / `delglobalconfig` |

响应统一信封：`{ code:0, msg, data }`，`code!=0` 视为失败。
