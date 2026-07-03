import 'package:flutter/material.dart';
import '../../../shared/themes/app_theme.dart';

// ── Local tool data ────────────────────────────────────────────────────────

class _LocalTool {
  _LocalTool({
    required this.name,
    required this.description,
    required this.authorized,
  });
  final String name;
  final String description;
  final bool authorized;
  bool enabled = false;
}

class _LocalSection {
  _LocalSection({required this.title, required this.tools});
  final String title;
  final List<_LocalTool> tools;
}

// ── Screen ─────────────────────────────────────────────────────────────────

class AddMcpScreen extends StatefulWidget {
  const AddMcpScreen({super.key});

  @override
  State<AddMcpScreen> createState() => _AddMcpScreenState();
}

class _AddMcpScreenState extends State<AddMcpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Remote tab state
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _authCtrl = TextEditingController();
  String _transport = 'SSE';
  bool _discovered = false;
  final List<_DiscoveredTool> _discoveredTools = [
    _DiscoveredTool(name: 'search_web', selected: true),
    _DiscoveredTool(name: 'fetch_page', selected: true),
    _DiscoveredTool(name: 'image_search', selected: false),
  ];

  // Local tab state
  final List<_LocalSection> _localSections = [
    _LocalSection(title: '位置 & 时间', tools: [
      _LocalTool(name: '获取当前位置', description: '读取设备 GPS 坐标', authorized: true),
      _LocalTool(name: '获取当前时间', description: '返回本地日期与时间', authorized: true),
      _LocalTool(name: '获取时区', description: '返回设备时区信息', authorized: true),
    ]),
    _LocalSection(title: '通讯录 & 系统', tools: [
      _LocalTool(name: '读取通讯录', description: '访问联系人列表', authorized: false),
      _LocalTool(name: '系统剪贴板', description: '读写剪贴板内容', authorized: true),
      _LocalTool(name: '获取设备信息', description: '型号、系统版本等', authorized: true),
    ]),
    _LocalSection(title: '相机 & 媒体', tools: [
      _LocalTool(name: '拍摄照片', description: '调用相机拍照', authorized: false),
      _LocalTool(name: '选择图片', description: '从相册选取图片', authorized: false),
      _LocalTool(name: '录制音频', description: '使用麦克风录音', authorized: false),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _authCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        title: const Text('添加 MCP 服务器'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.text2,
          indicatorColor: AppTheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: '远程服务器'),
            Tab(text: '内置工具'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RemoteTab(
            nameCtrl: _nameCtrl,
            urlCtrl: _urlCtrl,
            authCtrl: _authCtrl,
            transport: _transport,
            onTransportChanged: (v) => setState(() => _transport = v),
            discovered: _discovered,
            discoveredTools: _discoveredTools,
            onDiscover: _handleDiscover,
            onToolToggle: (i, v) => setState(() => _discoveredTools[i].selected = v),
            onSave: _handleSave,
          ),
          _LocalTab(
            sections: _localSections,
            onToolToggle: (sectionIndex, toolIndex, value) => setState(() {
              _localSections[sectionIndex].tools[toolIndex].enabled = value;
            }),
            onSave: _handleSaveLocal,
          ),
        ],
      ),
    );
  }

  void _handleDiscover() {
    if (_urlCtrl.text.trim().isEmpty) return;
    setState(() => _discovered = true);
  }

  void _handleSave() {
    if (_nameCtrl.text.trim().isEmpty || _urlCtrl.text.trim().isEmpty) return;
    Navigator.of(context).pop();
  }

  void _handleSaveLocal() {
    Navigator.of(context).pop();
  }
}

// ── Discovered tool model ──────────────────────────────────────────────────

class _DiscoveredTool {
  _DiscoveredTool({required this.name, required this.selected});
  final String name;
  bool selected;
}

// ── Remote tab ─────────────────────────────────────────────────────────────

class _RemoteTab extends StatelessWidget {
  const _RemoteTab({
    required this.nameCtrl,
    required this.urlCtrl,
    required this.authCtrl,
    required this.transport,
    required this.onTransportChanged,
    required this.discovered,
    required this.discoveredTools,
    required this.onDiscover,
    required this.onToolToggle,
    required this.onSave,
  });

  final TextEditingController nameCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController authCtrl;
  final String transport;
  final ValueChanged<String> onTransportChanged;
  final bool discovered;
  final List<_DiscoveredTool> discoveredTools;
  final VoidCallback onDiscover;
  final void Function(int index, bool value) onToolToggle;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FormCard(
            children: [
              _FieldLabel('名称'),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: '例如：GitHub MCP'),
              ),
              const SizedBox(height: 14),
              _FieldLabel('服务器地址'),
              TextField(
                controller: urlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(hintText: 'https://mcp.example.com'),
              ),
              const SizedBox(height: 14),
              _FieldLabel('传输方式'),
              _TransportSelector(
                current: transport,
                onChanged: onTransportChanged,
              ),
              const SizedBox(height: 14),
              _FieldLabel('认证头（可选）'),
              TextField(
                controller: authCtrl,
                decoration: const InputDecoration(
                  hintText: 'Bearer token...',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onDiscover,
              icon: const Icon(Icons.radar_outlined, size: 18),
              label: const Text('发现工具'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          if (discovered) ...[
            const SizedBox(height: 16),
            _SectionLabel('发现的工具'),
            _FormCard(
              children: [
                for (int i = 0; i < discoveredTools.length; i++)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      discoveredTools[i].name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.text1,
                        fontFamily: 'monospace',
                      ),
                    ),
                    value: discoveredTools[i].selected,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => onToolToggle(i, v ?? false),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transport segmented selector ───────────────────────────────────────────

class _TransportSelector extends StatelessWidget {
  const _TransportSelector({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  static const _options = ['SSE', 'HTTP', 'WS'];

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: _options
          .map((o) => ButtonSegment<String>(value: o, label: Text(o)))
          .toList(),
      selected: {current},
      onSelectionChanged: (v) => onChanged(v.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppTheme.primary
                : AppTheme.text2),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppTheme.primaryLight
                : Colors.transparent),
        side: WidgetStateProperty.all(
            const BorderSide(color: AppTheme.borderColor)),
      ),
    );
  }
}

// ── Local tab ──────────────────────────────────────────────────────────────

class _LocalTab extends StatelessWidget {
  const _LocalTab({
    required this.sections,
    required this.onToolToggle,
    required this.onSave,
  });

  final List<_LocalSection> sections;
  final void Function(int sectionIndex, int toolIndex, bool value) onToolToggle;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int si = 0; si < sections.length; si++) ...[
            _SectionLabel(sections[si].title),
            _FormCard(
              children: [
                for (int ti = 0; ti < sections[si].tools.length; ti++) ...[
                  if (ti > 0)
                    const Divider(height: 1, color: AppTheme.borderColor),
                  _LocalToolRow(
                    tool: sections[si].tools[ti],
                    onToggle: (v) => onToolToggle(si, ti, v),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                '保存',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalToolRow extends StatelessWidget {
  const _LocalToolRow({required this.tool, required this.onToggle});
  final _LocalTool tool;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AuthBadge(authorized: tool.authorized),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  tool.description,
                  style: const TextStyle(fontSize: 12, color: AppTheme.text2),
                ),
              ],
            ),
          ),
          Switch(
            value: tool.enabled,
            onChanged: onToggle,
            activeColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _AuthBadge extends StatelessWidget {
  const _AuthBadge({required this.authorized});
  final bool authorized;

  @override
  Widget build(BuildContext context) {
    final color = authorized ? AppTheme.success : AppTheme.warning;
    final label = authorized ? '已授权' : '需授权';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.text2,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.text2,
        ),
      ),
    );
  }
}
