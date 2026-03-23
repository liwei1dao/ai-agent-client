import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/themes/app_theme.dart';

// ── Data models ────────────────────────────────────────────────────────────

enum _McpType { remote, builtin }

class _McpServer {
  _McpServer({
    required this.name,
    required this.type,
    this.url,
    required this.tools,
    required this.enabled,
  });

  final String name;
  final _McpType type;
  final String? url;
  final List<String> tools;
  bool enabled;
}

// ── Screen ─────────────────────────────────────────────────────────────────

class McpServersScreen extends StatefulWidget {
  const McpServersScreen({super.key});

  @override
  State<McpServersScreen> createState() => _McpServersScreenState();
}

class _McpServersScreenState extends State<McpServersScreen> {
  final List<_McpServer> _servers = [
    _McpServer(
      name: 'GitHub MCP',
      type: _McpType.remote,
      url: 'mcp.github.com',
      tools: [
        'get_repo', 'list_issues', 'create_pr', 'list_commits',
        'get_file_content', 'search_code', 'list_branches',
        'get_user', 'list_releases', 'create_issue',
        'merge_pr', 'get_workflow',
      ],
      enabled: true,
    ),
    _McpServer(
      name: '本地工具',
      type: _McpType.builtin,
      tools: [
        'get_location', 'get_time', 'get_timezone', 'read_contacts',
        'clipboard', 'device_info', 'take_photo', 'pick_image',
      ],
      enabled: true,
    ),
    _McpServer(
      name: 'Web Search',
      type: _McpType.remote,
      url: 'search.mcp.io',
      tools: [
        'web_search', 'image_search', 'news_search',
        'scholar_search', 'fetch_page',
      ],
      enabled: false,
    ),
  ];

  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        title: const Text('MCP 服务器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/settings/mcp/add'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _servers.length,
        itemBuilder: (context, index) {
          return _ServerCard(
            server: _servers[index],
            isExpanded: _expanded.contains(index),
            onToggleExpand: () => setState(() {
              if (_expanded.contains(index)) {
                _expanded.remove(index);
              } else {
                _expanded.add(index);
              }
            }),
            onToggleEnabled: (value) => setState(() {
              _servers[index].enabled = value;
            }),
          );
        },
      ),
    );
  }
}

// ── Server card ────────────────────────────────────────────────────────────

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onToggleEnabled,
  });

  final _McpServer server;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _ServerHeader(
            server: server,
            isExpanded: isExpanded,
            onToggleExpand: onToggleExpand,
            onToggleEnabled: onToggleEnabled,
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.borderColor),
            _ToolList(tools: server.tools),
          ],
        ],
      ),
    );
  }
}

// ── Server header row ──────────────────────────────────────────────────────

class _ServerHeader extends StatelessWidget {
  const _ServerHeader({
    required this.server,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onToggleEnabled,
  });

  final _McpServer server;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final isRemote = server.type == _McpType.remote;
    final statusColor = server.enabled ? AppTheme.success : AppTheme.text2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),

          // Name + type chip + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TypeChip(isRemote: isRemote),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isRemote && server.url != null
                      ? '${server.url}  ·  ${server.tools.length} 个工具'
                      : '${server.tools.length} 个工具',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.text2,
                  ),
                ),
              ],
            ),
          ),

          // Enable switch
          Switch(
            value: server.enabled,
            onChanged: onToggleEnabled,
            activeColor: AppTheme.primary,
          ),

          // Expand / collapse arrow
          GestureDetector(
            onTap: onToggleExpand,
            child: AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(
                Icons.keyboard_arrow_down,
                color: AppTheme.text2,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Type chip pill ─────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.isRemote});
  final bool isRemote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isRemote
            ? AppTheme.translateAccent.withValues(alpha: 0.12)
            : AppTheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isRemote ? '远程' : '内置',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isRemote ? AppTheme.translateAccent : AppTheme.primary,
        ),
      ),
    );
  }
}

// ── Expanded tool list ─────────────────────────────────────────────────────

class _ToolList extends StatelessWidget {
  const _ToolList({required this.tools});
  final List<String> tools;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: tools.map((tool) => _ToolChip(name: tool)).toList(),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppTheme.text2,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
