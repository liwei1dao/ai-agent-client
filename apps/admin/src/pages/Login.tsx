import { useState } from 'react'
import { Form, Input, Button, Card, Typography } from 'antd'
import { UserOutlined, LockOutlined } from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { apiLogin } from '@/api/console'
import { useAuth } from '@/store/auth'

export default function Login() {
  const nav = useNavigate()
  const login = useAuth((s) => s.login)
  const [loading, setLoading] = useState(false)

  const onFinish = async (v: { account: string; password: string }) => {
    setLoading(true)
    try {
      const r = await apiLogin(v)
      login(r.token, r.account, r.identity)
      nav('/services')
    } catch {
      /* request.ts 已弹错误提示 */
    } finally {
      setLoading(false)
    }
  }

  return (
    <div
      style={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background:
          'radial-gradient(1200px 600px at 50% -10%, #e6f0ff 0%, #f5f7fb 45%, #f5f5f5 100%)',
      }}
    >
      <Card style={{ width: 380, borderRadius: 16, boxShadow: '0 12px 48px rgba(0,21,41,.12)' }}>
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div
            style={{
              width: 56,
              height: 56,
              borderRadius: 14,
              margin: '0 auto 12px',
              background: 'linear-gradient(135deg,#1677ff,#36cfc9)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 28,
            }}
          >
            🤖
          </div>
          <Typography.Title level={4} style={{ margin: 0 }}>
            UniHelper 管理后台
          </Typography.Title>
          <Typography.Text type="secondary">服务与 Agent 配置中心</Typography.Text>
        </div>

        <Form layout="vertical" initialValues={{ account: 'admin' }} onFinish={onFinish}>
          <Form.Item name="account" label="账号" rules={[{ required: true, message: '请输入账号' }]}>
            <Input prefix={<UserOutlined />} placeholder="请输入账号" size="large" />
          </Form.Item>
          <Form.Item name="password" label="密码" rules={[{ required: true, message: '请输入密码' }]}>
            <Input.Password prefix={<LockOutlined />} placeholder="请输入密码" size="large" />
          </Form.Item>
          <Button type="primary" htmlType="submit" block size="large" loading={loading}>
            登 录
          </Button>
        </Form>
      </Card>
    </div>
  )
}
