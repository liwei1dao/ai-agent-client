import { useEffect, useState } from 'react'
import {
  Card,
  Form,
  Input,
  Select,
  Switch,
  Button,
  Space,
  Radio,
  Divider,
  message,
  Typography,
} from 'antd'
import { PlusOutlined, MinusCircleOutlined, ArrowLeftOutlined } from '@ant-design/icons'
import { useNavigate, useParams } from 'react-router-dom'
import { apiGetAgents, apiAddAgent, apiUpdateAgent, apiGetSvcConfigs } from '@/api/console'
import { type VoitransAgent, AGENT_TYPES } from '@/api/types'

const LANGS = ['中文', 'English', '日本語', '한국어', 'Français', 'Español', 'Deutsch', 'Русский']

export default function AgentEdit() {
  const nav = useNavigate()
  const { id } = useParams()
  const editing = !!id
  const [form] = Form.useForm()
  const [saving, setSaving] = useState(false)
  const [svcOptions, setSvcOptions] = useState<{ value: string; label: string }[]>([])

  useEffect(() => {
    apiGetSvcConfigs()
      .then((list) =>
        setSvcOptions(list.map((s) => ({ value: s.id, label: `${s.name}（${s.id}）` }))),
      )
      .catch(() => {})

    if (editing) {
      apiGetAgents()
        .then((list) => {
          const a = list.find((x) => x.agent_id === id)
          if (a) form.setFieldsValue(a)
        })
        .catch(() => {})
    } else {
      form.setFieldsValue({
        type: 'agent_chat',
        enable: true,
        supported_languages: ['中文', 'English'],
        variables: [],
      })
    }
  }, [id])

  const onSave = async () => {
    const v = (await form.validateFields()) as VoitransAgent
    setSaving(true)
    try {
      if (editing) await apiUpdateAgent(v)
      else await apiAddAgent(v)
      message.success(editing ? '已更新' : '已创建')
      nav('/agents')
    } catch {
      /* ignore */
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16 }}>
        <Typography.Title level={4} style={{ margin: 0 }}>
          {editing ? '编辑 Agent' : '创建 Agent'}
        </Typography.Title>
        <Button icon={<ArrowLeftOutlined />} onClick={() => nav('/agents')}>
          返回列表
        </Button>
      </div>

      <Card>
        <Form form={form} layout="vertical" style={{ maxWidth: 720 }}>
          <Form.Item name="type" label="类型" rules={[{ required: true }]}>
            <Radio.Group optionType="button" buttonStyle="solid">
              {Object.entries(AGENT_TYPES).map(([k, v]) => (
                <Radio.Button key={k} value={k}>
                  {v.icon} {v.label}
                </Radio.Button>
              ))}
            </Radio.Group>
          </Form.Item>

          <Space style={{ display: 'flex' }} align="start">
            <Form.Item name="name" label="Agent 名称" rules={[{ required: true }]} style={{ flex: 1 }}>
              <Input placeholder="例如：通用助手" style={{ width: 340 }} />
            </Form.Item>
            <Form.Item name="agent_id" label="Agent ID（唯一）" rules={[{ required: true }]}>
              <Input placeholder="agt_general_chat" disabled={editing} style={{ width: 340 }} />
            </Form.Item>
          </Space>

          <Form.Item name="avatar_url" label="头像 URL">
            <Input placeholder="https://cdn.example.com/avatar.png" />
          </Form.Item>
          <Form.Item name="description" label="描述">
            <Input.TextArea rows={2} placeholder="一句话说明这个 Agent 的能力" />
          </Form.Item>
          <Form.Item name="supported_languages" label="支持语言" rules={[{ required: true }]}>
            <Select mode="tags" options={LANGS.map((l) => ({ value: l, label: l }))} placeholder="选择或输入" />
          </Form.Item>

          <Divider orientation="left" plain style={{ fontSize: 13 }}>
            变量（variables[]，运行时由客户端填入）
          </Divider>
          <Form.List name="variables">
            {(fields, { add, remove }) => (
              <>
                {fields.map((field) => (
                  <Space key={field.key} align="baseline" style={{ display: 'flex', marginBottom: 8 }}>
                    <Form.Item name={[field.name, 'name']} rules={[{ required: true, message: '变量名' }]} style={{ marginBottom: 0 }}>
                      <Input placeholder="变量名" style={{ width: 140 }} />
                    </Form.Item>
                    <Form.Item name={[field.name, 'type']} initialValue="string" style={{ marginBottom: 0 }}>
                      <Select style={{ width: 100 }} options={[{ value: 'string' }, { value: 'number' }, { value: 'bool' }]} />
                    </Form.Item>
                    <Form.Item name={[field.name, 'required']} valuePropName="checked" style={{ marginBottom: 0 }}>
                      <Switch size="small" checkedChildren="必填" unCheckedChildren="选填" />
                    </Form.Item>
                    <Form.Item name={[field.name, 'default_value']} style={{ marginBottom: 0 }}>
                      <Input placeholder="默认值 / 描述" style={{ width: 200 }} />
                    </Form.Item>
                    <MinusCircleOutlined onClick={() => remove(field.name)} style={{ color: '#999' }} />
                  </Space>
                ))}
                <Button type="dashed" onClick={() => add({ type: 'string', required: false })} block icon={<PlusOutlined />}>
                  添加变量
                </Button>
              </>
            )}
          </Form.List>

          <Divider orientation="left" plain style={{ fontSize: 13 }}>
            绑定服务
          </Divider>
          <Space style={{ display: 'flex' }} align="start">
            <Form.Item name="llm_svc_id" label="LLM 服务" style={{ flex: 1 }}>
              <Select allowClear options={svcOptions} placeholder="选择已配置服务" style={{ width: 340 }} />
            </Form.Item>
            <Form.Item name="tts_svc_id" label="语音/TTS 服务">
              <Select allowClear options={svcOptions} placeholder="选填" style={{ width: 340 }} />
            </Form.Item>
          </Space>

          <Form.Item name="enable" label="启用" valuePropName="checked">
            <Switch />
          </Form.Item>

          <Space>
            <Button onClick={() => nav('/agents')}>取消</Button>
            <Button type="primary" loading={saving} onClick={onSave}>
              {editing ? '保存' : '创建 Agent'}
            </Button>
          </Space>
        </Form>
      </Card>
    </>
  )
}
