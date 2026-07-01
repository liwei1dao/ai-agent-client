import { useEffect, useState } from 'react'
import {
  Card,
  Table,
  Button,
  Tag,
  Space,
  Switch,
  Drawer,
  Form,
  Input,
  Select,
  Popconfirm,
  message,
  Typography,
} from 'antd'
import { PlusOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import {
  apiGetMcpServers,
  apiAddMcpServer,
  apiUpdateMcpServer,
  apiDelMcpServer,
} from '@/api/console'
import type { McpServer } from '@/api/types'

export default function Mcp() {
  const [data, setData] = useState<McpServer[]>([])
  const [loading, setLoading] = useState(false)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<McpServer | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await apiGetMcpServers())
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    load()
  }, [])

  const openCreate = () => {
    setEditing(null)
    form.resetFields()
    form.setFieldsValue({ enable: true, transport: 'sse' })
    setOpen(true)
  }
  const openEdit = (row: McpServer) => {
    setEditing(row)
    form.setFieldsValue(row)
    setOpen(true)
  }
  const onSave = async () => {
    const v = (await form.validateFields()) as McpServer
    try {
      if (editing) await apiUpdateMcpServer(v)
      else await apiAddMcpServer(v)
      message.success(editing ? '已更新' : '已创建')
      setOpen(false)
      load()
    } catch {
      /* ignore */
    }
  }

  const columns: ColumnsType<McpServer> = [
    {
      title: '状态',
      dataIndex: 'enable',
      width: 70,
      render: (v, row) => (
        <Switch
          checked={v}
          size="small"
          onChange={async (c) => {
            await apiUpdateMcpServer({ ...row, enable: c })
            setData((d) => d.map((x) => (x.id === row.id ? { ...x, enable: c } : x)))
          }}
        />
      ),
    },
    {
      title: '名称',
      dataIndex: 'name',
      render: (v, row) => (
        <>
          <div style={{ fontWeight: 500 }}>{v}</div>
          <code style={{ fontSize: 12 }}>{row.id}</code>
        </>
      ),
    },
    {
      title: '类型',
      dataIndex: 'transport',
      render: (v: string) =>
        v === 'sse' ? <Tag color="blue">远程 SSE</Tag> : <Tag color="purple">本地 stdio</Tag>,
    },
    { title: '地址 / 命令', dataIndex: 'endpoint', render: (v) => <code style={{ fontSize: 12 }}>{v}</code> },
    {
      title: '工具',
      dataIndex: 'tool_count',
      width: 90,
      render: (v) => <Tag color="gold">{v ?? 0} 工具</Tag>,
    },
    {
      title: '操作',
      width: 150,
      render: (_, row) => (
        <Space size={4}>
          <Button type="link" size="small" onClick={() => openEdit(row)}>
            编辑
          </Button>
          <Popconfirm title="确认删除？" onConfirm={async () => { await apiDelMcpServer(row.id); message.success('已删除'); load() }}>
            <Button type="link" size="small" danger>
              删除
            </Button>
          </Popconfirm>
        </Space>
      ),
    },
  ]

  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16 }}>
        <div>
          <Typography.Title level={4} style={{ margin: 0 }}>
            MCP 配置
          </Typography.Title>
          <Typography.Text type="secondary">
            Model Context Protocol 工具服务（mcp_server），供 Agent 调用外部工具
          </Typography.Text>
        </div>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          接入 MCP
        </Button>
      </div>

      <Card styles={{ body: { padding: 0 } }}>
        <Table rowKey="id" loading={loading} columns={columns} dataSource={data} pagination={{ pageSize: 10 }} />
      </Card>

      <Drawer
        title={editing ? '编辑 MCP' : '接入 MCP'}
        width={520}
        open={open}
        onClose={() => setOpen(false)}
        extra={
          <Space>
            <Button onClick={() => setOpen(false)}>取消</Button>
            <Button type="primary" onClick={onSave}>
              保存
            </Button>
          </Space>
        }
      >
        <Form form={form} layout="vertical">
          <Form.Item name="name" label="名称" rules={[{ required: true }]}>
            <Input placeholder="例如：高德地图" />
          </Form.Item>
          <Form.Item name="id" label="ID（唯一）" rules={[{ required: true }]}>
            <Input placeholder="amap_mcp" disabled={!!editing} />
          </Form.Item>
          <Form.Item name="transport" label="传输类型" rules={[{ required: true }]}>
            <Select
              options={[
                { value: 'sse', label: '远程 SSE' },
                { value: 'stdio', label: '本地 stdio' },
              ]}
            />
          </Form.Item>
          <Form.Item name="endpoint" label="地址 / 命令" rules={[{ required: true }]}>
            <Input placeholder="https://mcp.amap.com/sse 或 npx -y @mcp/server-xxx" />
          </Form.Item>
          <Form.Item name="enable" label="启用" valuePropName="checked">
            <Switch />
          </Form.Item>
        </Form>
      </Drawer>
    </>
  )
}
