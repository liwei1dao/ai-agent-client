class MeetingTemplate {
  const MeetingTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.prompt,
    this.builtin = false,
    this.icon = 'description',
  });

  final String id;
  final String name;
  final String description;
  final String prompt;
  final bool builtin;
  final String icon;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'prompt': prompt,
        'builtin': builtin,
        'icon': icon,
      };

  factory MeetingTemplate.fromJson(Map<String, dynamic> json) =>
      MeetingTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        builtin: json['builtin'] as bool? ?? false,
        icon: json['icon'] as String? ?? 'description',
      );

  MeetingTemplate copyWith({
    String? name,
    String? description,
    String? prompt,
  }) =>
      MeetingTemplate(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        prompt: prompt ?? this.prompt,
        builtin: builtin,
        icon: icon,
      );
}

const kBuiltInTemplates = <MeetingTemplate>[
  MeetingTemplate(
    id: 'builtin_general',
    name: '通用会议',
    description: '适用于绝大多数会议场景',
    icon: 'description',
    builtin: true,
    prompt: '请将这段会议转写整理成结构化纪要，包含：会议主题、关键决策、待办事项、责任人与截止时间。',
  ),
  MeetingTemplate(
    id: 'builtin_standup',
    name: '每日站会',
    description: '昨日完成 / 今日计划 / 阻塞',
    icon: 'group',
    builtin: true,
    prompt: '请按"昨日完成 / 今日计划 / 当前阻塞"三段提炼每位成员的发言。',
  ),
  MeetingTemplate(
    id: 'builtin_interview',
    name: '面试访谈',
    description: '提取候选人优势与风险点',
    icon: 'person_search',
    builtin: true,
    prompt: '请按"候选人背景 / 技术亮点 / 软技能 / 风险点 / 录用建议"输出。',
  ),
  MeetingTemplate(
    id: 'builtin_brainstorm',
    name: '头脑风暴',
    description: '聚类创意 + 投票',
    icon: 'lightbulb',
    builtin: true,
    prompt: '请把会议中提到的创意按主题聚类，每个创意附一句价值评估。',
  ),
];
