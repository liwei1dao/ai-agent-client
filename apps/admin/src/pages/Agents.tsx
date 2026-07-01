import { useEffect, useState } from 'react'
import { Row, Col, Card, Button, Tag, Typography, Empty, Spin, Popconfirm, message, Space } from 'antd'
import { PlusOutlined } from '@ant-design/icons'
import { useNavigate } from 'react-router-dom'
import { apiGetAgents, apiDelAgent } from '@/api/console'
import { type VoitransAgent, AGENT_TYPES } from '@/api/types'

export default function Agents() {
  const nav = useNavigate()
  const [data, setData] = useState<VoitransAgent[]>([])
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try {
      setData(await apiGetAgents())
    } catch {
      /* ignore */
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    load()
  }, [])

  const del = async (id: string) => {
    await apiDelAgent(id)
    message.success('已删除')
    load()
  }

  return (
    <>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 16 }}>
        <div>
          <Typography.Title level={4} style={{ margin: 0 }}>
            Agent 配置
          </Typography.Title>
          <Typography.Text type="secondary">
            智能体定义（DBVoitransAgent）：chat / sts-chat / translate / ast-translate
          </Typography.Text>
        </div>
        <Button type="primary" icon={<PlusOutlined />} onClick={() => nav('/agents/new')}>
          创建 Agent
        </Button>
      </div>

      <Spin spinning={loading}>
        {data.length === 0 && !loading ? (
          <Card>
            <Empty description="还没有 Agent">
              <Button type="primary" onClick={() => nav('/agents/new')}>
                创建第一个 Agent
              </Button>
            </Empty>
          </Card>
        ) : (
          <Row gutter={[16, 16]}>
            {data.map((a) => {
              const t = AGENT_TYPES[a.type]
              return (
                <Col key={a.agent_id} xs={24} sm={12} lg={8} xxl={6}>
                  <Card
                    hoverable
                    actions={[
                      <a key="edit" onClick={() => nav(`/agents/edit/${a.agent_id}`)}>
                        编辑
                      </a>,
                      <Popconfirm key="del" title="确认删除该 Agent？" onConfirm={() => del(a.agent_id)}>
                        <a style={{ color: '#ff4d4f' }}>删除</a>
                      </Popconfirm>,
                    ]}
                  >
                    <Card.Meta
                      avatar={
                        <div
                          style={{
                            width: 44,
                            height: 44,
                            borderRadius: 10,
                            background: '#e6f4ff',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            fontSize: 22,
                          }}
                        >
                          {t?.icon || '🤖'}
                        </div>
                      }
                      title={a.name}
                      description={<code style={{ fontSize: 12 }}>{a.agent_id}</code>}
                    />
                    <Typography.Paragraph
                      type="secondary"
                      ellipsis={{ rows: 2 }}
                      style={{ margin: '12px 0', minHeight: 40 }}
                    >
                      {a.description}
                    </Typography.Paragraph>
                    <Space size={4} wrap>
                      <Tag color={t?.color}>{a.type}</Tag>
                      <Tag>🌐 {(a.supported_languages || []).length} 语言</Tag>
                      <Tag color="gold">{(a.variables || []).length} 变量</Tag>
                    </Space>
                  </Card>
                </Col>
              )
            })}
          </Row>
        )}
      </Spin>
    </>
  )
}
