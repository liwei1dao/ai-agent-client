import { Layout, Menu, Avatar, Dropdown, theme } from 'antd'
import {
  ApiOutlined,
  RobotOutlined,
  ClusterOutlined,
  SettingOutlined,
  LogoutOutlined,
} from '@ant-design/icons'
import { useNavigate, useLocation, Outlet } from 'react-router-dom'
import { useAuth } from '@/store/auth'

const { Sider, Header, Content } = Layout

const MENU = [
  { key: '/services', icon: <ApiOutlined />, label: '服务配置' },
  { key: '/agents', icon: <RobotOutlined />, label: 'Agent 配置' },
  { key: '/mcp', icon: <ClusterOutlined />, label: 'MCP 配置' },
  { key: '/global', icon: <SettingOutlined />, label: '全局配置' },
]

const IDENTITY: Record<number, string> = { 1: '超管', 2: '管理员', 3: '代理商', 4: '运营' }

export default function AdminLayout() {
  const nav = useNavigate()
  const loc = useLocation()
  const { account, identity, logout } = useAuth()
  const { token } = theme.useToken()

  // 选中项：取一级路径（/agents/new 也高亮 /agents）
  const selected = '/' + (loc.pathname.split('/')[1] || 'services')

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider theme="dark" width={220}>
        <div
          style={{
            height: 64,
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            padding: '0 20px',
            color: '#fff',
            fontSize: 16,
            fontWeight: 600,
          }}
        >
          <span
            style={{
              width: 30,
              height: 30,
              borderRadius: 7,
              background: 'linear-gradient(135deg,#1677ff,#36cfc9)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            🤖
          </span>
          UniHelper 后台
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[selected]}
          items={MENU}
          onClick={({ key }) => nav(key)}
        />
      </Sider>

      <Layout>
        <Header
          style={{
            background: token.colorBgContainer,
            padding: '0 24px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'flex-end',
            boxShadow: '0 1px 4px rgba(0,21,41,.06)',
          }}
        >
          <Dropdown
            menu={{
              items: [{ key: 'logout', icon: <LogoutOutlined />, label: '退出登录' }],
              onClick: () => {
                logout()
                nav('/login')
              },
            }}
          >
            <span style={{ cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 8 }}>
              <Avatar size={32} style={{ background: token.colorPrimary }}>
                {account.slice(0, 1).toUpperCase() || 'A'}
              </Avatar>
              <span style={{ color: 'rgba(0,0,0,.65)' }}>
                {account || 'admin'}（{IDENTITY[identity] || '—'}）
              </span>
            </span>
          </Dropdown>
        </Header>

        <Content style={{ margin: 24 }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  )
}
