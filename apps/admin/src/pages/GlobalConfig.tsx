import { useEffect, useState } from 'react'
import {
  Card,
  Table,
  Button,
  Tag,
  Space,
  Switch,
  Modal,
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
  apiGetGlobalConfigs,
  apiAddGlobalConfig,
  apiUpdateGlobalConfig,
  apiDelGlobalConfig,
} from '@/api/console'
import type { GlobalConfigItem } from '@/api/types'

const TYPE_COLOR: Record<string, string> = { string: 'default', number: 'blue', bool: 'green' }

export default function GlobalConfig() {
  const [data, setData] = useState<GlobalConfigItem[]>([])
  const [loading, setLoading] = useState(false)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<GlobalConfigItem | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await apiGetGlobalConfigs())
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
    form.setFieldsValue({ type: 'string', group: '系统' })
    setOpen(true)
  }
  const openEdit = (row: GlobalConfigItem) => {
    setEditing(row)
    form.setFieldsValue(row)
    setOpen(true)
  }
  const onSave = async () => {
    const v = (await form.validateFields()) as GlobalConfigItem
    try {
      if (editing) await apiUpdateGlobalConfig({ ...editing, ...v })
      else await apiAddGlobalConfig(v)
      message.success(editing ? '已更新' : '已创建')
      setOpen(false)
      load()
    } catch {
      /* ignore */
    }
  }

  const columns: ColumnsType<GlobalConfigItem> = [
    { title: '分组', dataIndex: 'group', width: 100, render: (v) => <Tag>{v}</Tag> },
    { title: 'Key', dataIndex: 'key', render: (v) => <code>{v}</code> },
    {
      title: 'Value',
      dataIndex: 'value',
      render: (v, row) =>
        row.type === 'bool' ? (
          <Switch checked={v === 'true' || v === '1'} disabled size="small" />
        ) : (
          <span style={{ fontWeight: 500 }}>{v}</span>
        ),
    },
    {
      title: '类型',
      dataIndex: 'type',
      width: 90,
      render: (v: string) => <Tag color={TYPE_COLOR[v]}>{v}</Tag>,
    },
    { title: '描述', dataIndex: 'description', ellipsis: true },
    {
      title: '操作',
      width: 150,
      render: (_, row) => (
        <Space size={4}>
          <Button type="link" size="small" onClick={() => openEdit(row)}>
            编辑
          </Button>
          <Popconfirm title="确认删除？" onConfirm={async () => { await apiDelGlobalConfig(row.id!); message.success('已删除'); load() }}>
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
            全局配置
          </Typography.Title>
          <Typography.Text type="secondary">
            系统级键值配置（global_config），变更经 NATS 下发到业务服务
          </Typography.Text>
        </div>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          新建配置项
        </Button>
      </div>

      <Card styles={{ body: { padding: 0 } }}>
        <Table rowKey={(r) => String(r.id ?? r.key)} loading={loading} columns={columns} dataSource={data} pagination={{ pageSize: 12 }} />
      </Card>

      <Modal
        title={editing ? '编辑配置项' : '新建配置项'}
        open={open}
        onCancel={() => setOpen(false)}
        onOk={onSave}
        destroyOnClose
      >
        <Form form={form} layout="vertical" style={{ marginTop: 12 }}>
          <Space style={{ display: 'flex' }} align="start">
            <Form.Item name="group" label="分组" rules={[{ required: true }]}>
              <Input placeholder="系统 / 计费 / 功能开关" style={{ width: 200 }} />
            </Form.Item>
            <Form.Item name="type" label="类型" rules={[{ required: true }]}>
              <Select
                style={{ width: 140 }}
                options={[{ value: 'string' }, { value: 'number' }, { value: 'bool' }]}
              />
            </Form.Item>
          </Space>
          <Form.Item name="key" label="Key" rules={[{ required: true }]}>
            <Input placeholder="default_llm_svc" disabled={!!editing} />
          </Form.Item>
          <Form.Item name="value" label="Value" rules={[{ required: true }]}>
            <Input placeholder="配置值（bool 填 true/false）" />
          </Form.Item>
          <Form.Item name="description" label="描述">
            <Input placeholder="用途说明" />
          </Form.Item>
        </Form>
      </Modal>
    </>
  )
}
