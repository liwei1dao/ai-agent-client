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
  Divider,
} from 'antd'
import { PlusOutlined, MinusCircleOutlined } from '@ant-design/icons'
import type { ColumnsType } from 'antd/es/table'
import {
  apiGetSvcConfigs,
  apiAddSvcConfig,
  apiUpdateSvcConfig,
  apiDelSvcConfig,
} from '@/api/console'
import { type ThirdSvcConfig, SVC_CATEGORIES } from '@/api/types'

const CAT_OPTIONS = Object.entries(SVC_CATEGORIES).map(([value, v]) => ({ value, label: v.label }))

export default function Services() {
  const [data, setData] = useState<ThirdSvcConfig[]>([])
  const [loading, setLoading] = useState(false)
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<ThirdSvcConfig | null>(null)
  const [form] = Form.useForm()

  const load = async () => {
    setLoading(true)
    try {
      setData(await apiGetSvcConfigs())
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
    form.setFieldsValue({ enable: true, categories: ['1'], fields: [{ key: '', encrypted: false }] })
    setOpen(true)
  }
  const openEdit = (row: ThirdSvcConfig) => {
    setEditing(row)
    form.setFieldsValue({ ...row, categories: row.categories ? row.categories.split(',') : [] })
    setOpen(true)
  }

  const onSave = async () => {
    const v = await form.validateFields()
    const payload: ThirdSvcConfig = {
      ...v,
      categories: (v.categories || []).join(','),
      fields: (v.fields || []).map((f: ThirdSvcConfig['fields'][number], i: number) => ({
        ...f,
        sort: i,
        description: f.description || '',
        def_value: f.def_value || '',
        encrypted: !!f.encrypted,
      })),
    }
    try {
      if (editing) await apiUpdateSvcConfig(payload)
      else await apiAddSvcConfig(payload)
      message.success(editing ? '已更新' : '已创建')
      setOpen(false)
      load()
    } catch {
      /* ignore */
    }
  }

  const onToggle = async (row: ThirdSvcConfig, enable: boolean) => {
    await apiUpdateSvcConfig({ ...row, enable })
    setData((d) => d.map((x) => (x.id === row.id ? { ...x, enable } : x)))
  }

  const columns: ColumnsType<ThirdSvcConfig> = [
    {
      title: '状态',
      dataIndex: 'enable',
      width: 70,
      render: (v, row) => <Switch checked={v} size="small" onChange={(c) => onToggle(row, c)} />,
    },
    {
      title: '服务名称',
      dataIndex: 'name',
      render: (v, row) => (
        <>
          <div style={{ fontWeight: 500 }}>{v}</div>
          <Typography.Text type="secondary" style={{ fontSize: 12 }}>
            {row.description}
          </Typography.Text>
        </>
      ),
    },
    {
      title: '类别',
      dataIndex: 'categories',
      render: (v: string) =>
        (v || '')
          .split(',')
          .filter(Boolean)
          .map((c) => (
            <Tag key={c} color={SVC_CATEGORIES[c]?.color}>
              {SVC_CATEGORIES[c]?.label || c}
            </Tag>
          )),
    },
    { title: '服务 ID', dataIndex: 'id', render: (v) => <code>{v}</code> },
    {
      title: '字段',
      dataIndex: 'fields',
      render: (f: ThirdSvcConfig['fields']) => {
        const enc = (f || []).filter((x) => x.encrypted).length
        return (
          <Space size={4}>
            <Tag>{(f || []).length} 字段</Tag>
            {enc > 0 && <Tag color="gold">🔒 {enc}</Tag>}
          </Space>
        )
      },
    },
    {
      title: '操作',
      width: 170,
      render: (_, row) => (
        <Space size={4}>
          <Button type="link" size="small" onClick={() => openEdit(row)}>
            编辑
          </Button>
          <Popconfirm title="确认删除该服务？" onConfirm={async () => { await apiDelSvcConfig(row.id); message.success('已删除'); load() }}>
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
            服务配置
          </Typography.Title>
          <Typography.Text type="secondary">
            管理 LLM / STT / TTS / AST 等第三方供应商服务（third_svc_config）
          </Typography.Text>
        </div>
        <Button type="primary" icon={<PlusOutlined />} onClick={openCreate}>
          新建服务
        </Button>
      </div>

      <Card styles={{ body: { padding: 0 } }}>
        <Table rowKey="id" loading={loading} columns={columns} dataSource={data} pagination={{ pageSize: 10 }} />
      </Card>

      <Drawer
        title={editing ? '编辑服务' : '新建服务'}
        width={560}
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
          <Form.Item name="name" label="服务名称" rules={[{ required: true }]}>
            <Input placeholder="例如：火山方舟 · Doubao" />
          </Form.Item>
          <Form.Item name="id" label="服务 ID（唯一）" rules={[{ required: true }]}>
            <Input placeholder="volc_ark_llm" disabled={!!editing} />
          </Form.Item>
          <Form.Item name="categories" label="类别" rules={[{ required: true }]}>
            <Select mode="multiple" options={CAT_OPTIONS} placeholder="可多选" />
          </Form.Item>
          <Form.Item name="description" label="描述">
            <Input.TextArea rows={2} placeholder="服务用途说明" />
          </Form.Item>
          <Form.Item name="enable" label="启用" valuePropName="checked">
            <Switch />
          </Form.Item>

          <Divider orientation="left" plain style={{ fontSize: 13 }}>
            服务字段（fields[]，🔒 字段将 AES 加密落库）
          </Divider>

          <Form.List name="fields">
            {(fields, { add, remove }) => (
              <>
                {fields.map((field) => (
                  <Space key={field.key} align="baseline" style={{ display: 'flex', marginBottom: 8 }}>
                    <Form.Item name={[field.name, 'key']} rules={[{ required: true, message: 'key' }]} style={{ marginBottom: 0 }}>
                      <Input placeholder="字段 Key" style={{ width: 130 }} />
                    </Form.Item>
                    <Form.Item name={[field.name, 'def_value']} style={{ marginBottom: 0 }}>
                      <Input placeholder="默认值" style={{ width: 180 }} />
                    </Form.Item>
                    <Form.Item name={[field.name, 'encrypted']} valuePropName="checked" style={{ marginBottom: 0 }}>
                      <Switch size="small" checkedChildren="🔒" />
                    </Form.Item>
                    <MinusCircleOutlined onClick={() => remove(field.name)} style={{ color: '#999' }} />
                  </Space>
                ))}
                <Button type="dashed" onClick={() => add({ encrypted: false })} block icon={<PlusOutlined />}>
                  添加字段
                </Button>
              </>
            )}
          </Form.List>
        </Form>
      </Drawer>
    </>
  )
}
