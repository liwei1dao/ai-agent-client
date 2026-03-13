import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TranslateAgentScreen extends ConsumerWidget {
  const TranslateAgentScreen({super.key, required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('翻译 Agent')),
      body: Column(
        children: [
          // 语言选择栏
          _LanguageBar(),
          const Divider(height: 1),
          // 翻译结果列表
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                _TranslationCard(
                  source: '还没有翻译记录',
                  target: '',
                  sourceLang: 'zh',
                  targetLang: 'en',
                ),
              ],
            ),
          ),
          // 输入栏
          _CallModeBar(),
        ],
      ),
    );
  }
}

class _LanguageBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('中文'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.swap_horiz),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              child: const Text('English'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.source,
    required this.target,
    required this.sourceLang,
    required this.targetLang,
  });

  final String source;
  final String target;
  final String sourceLang;
  final String targetLang;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source, style: Theme.of(context).textTheme.bodyLarge),
            if (target.isNotEmpty) ...[
              const Divider(),
              Text(target,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CallModeBar extends StatefulWidget {
  @override
  State<_CallModeBar> createState() => _CallModeBarState();
}

class _CallModeBarState extends State<_CallModeBar> {
  bool _inCall = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _inCall
                  ? Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      alignment: Alignment.center,
                      child: const Text('同传模式监听中…'),
                    )
                  : const SizedBox.shrink(),
            ),
            if (_inCall) const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => setState(() => _inCall = !_inCall),
              icon: Icon(_inCall ? Icons.call_end : Icons.call),
              label: Text(_inCall ? '结束同传' : '开始同传'),
              style: FilledButton.styleFrom(
                backgroundColor: _inCall ? Colors.red : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
