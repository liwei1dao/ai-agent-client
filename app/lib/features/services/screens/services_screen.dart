import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:local_db/local_db.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:stt_azure/stt_azure.dart';
import 'package:agent_runtime/agent_runtime.dart' hide SttEvent, LlmEvent;
import 'package:agent_runtime/agent_runtime.dart' as rt show SttEvent, LlmEvent;
import '../../../shared/themes/app_theme.dart';
import '../providers/service_library_provider.dart';
import '../widgets/add_service_modal.dart';

class _VoiceInfo {
  const _VoiceInfo({required this.shortName, required this.displayName, required this.locale});
  final String shortName;
  final String displayName;
  final String locale;
}

// ── Badge colors matching HTML mockup ────────────────────────────────────────
Color _typeBg(String type) => switch (type) {
      'stt' => const Color(0xFFFEF3C7),
      'tts' => const Color(0xFFF0FDF4),
      'llm' => const Color(0xFFFAF5FF),
      'translation' => const Color(0xFFEFF6FF),
      'sts' => const Color(0xFFEEF0FF),
      'ast' => const Color(0xFFFFF7ED),
      'mcp' => const Color(0xFFE8F5E9),
      _ => const Color(0xFFF3F4F6),
    };

Color _typeFg(String type) => switch (type) {
      'stt' => const Color(0xFF92400E),
      'tts' => const Color(0xFF14532D),
      'llm' => const Color(0xFF6B21A8),
      'translation' => const Color(0xFF1D4ED8),
      'sts' => const Color(0xFF4A42D9),
      'ast' => const Color(0xFF9A3412),
      'mcp' => const Color(0xFF1B5E20),
      _ => AppTheme.text2,
    };

String _typeLabel(String type) => switch (type) {
      'stt' => 'STT',
      'tts' => 'TTS',
      'llm' => 'LLM',
      'translation' => '翻译',
      'sts' => 'STS',
      'ast' => 'AST',
      'mcp' => 'MCP',
      _ => type.toUpperCase(),
    };

String _typeSectionLabel(String type) => switch (type) {
      'stt' => '语音识别 STT',
      'tts' => '语音合成 TTS',
      'llm' => '大语言模型 LLM',
      'translation' => '翻译服务',
      'sts' => '语音转语音 STS',
      'ast' => '端到端翻译 AST',
      'mcp' => 'MCP 服务',
      _ => type.toUpperCase(),
    };

// ── Main screen ──────────────────────────────────────────────────────────────

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(serviceLibraryProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('服务中心',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            Text('已配置 ${services.length} 个服务',
                style: const TextStyle(fontSize: 11, color: AppTheme.text2, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _showAddModal(context),
              child: Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppTheme.primary, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: services.isEmpty ? _buildEmpty(context) : _buildContent(context, services),
    );
  }

  void _showAddModal(BuildContext context, {ServiceConfigDto? service}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddServiceModal(initialService: service),
    );
  }

  void _navigateToServiceTest(BuildContext context, ServiceConfigDto service) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ServiceTestScreen(service: service),
    ));
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.grid_view_rounded, size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          const Text('还没有配置服务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.text1)),
          const SizedBox(height: 6),
          const Text('点击右上角 + 添加 STT / TTS / LLM 等服务',
              style: TextStyle(fontSize: 12, color: AppTheme.text2)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showAddModal(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加第一个服务'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ServiceConfigDto> services) {
    final groups = <String, List<ServiceConfigDto>>{};
    for (final s in services) {
      groups.putIfAbsent(s.type, () => []).add(s);
    }
    const typeOrder = ['llm', 'stt', 'tts', 'translation', 'sts', 'ast', 'mcp'];
    final sortedTypes = [
      ...typeOrder.where(groups.containsKey),
      ...groups.keys.where((t) => !typeOrder.contains(t)),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        // ── Configured services ──
        Row(
          children: [
            const Text('已配置服务',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            const Spacer(),
            Text('${services.length} 个',
                style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
          ],
        ),
        const SizedBox(height: 10),
        for (final type in sortedTypes) ...[
          // Type row header
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _TypeBadge(type: type),
                const SizedBox(width: 6),
                Text('(${groups[type]!.length})',
                    style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
              ],
            ),
          ),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.9,
            ),
            itemCount: groups[type]!.length,
            itemBuilder: (_, j) => _ServiceCard(
              service: groups[type]![j],
              onTap: () => _navigateToServiceTest(context, groups[type]![j]),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

// ── Service test screen (full page, per service) ────────────────────────────

class ServiceTestScreen extends StatelessWidget {
  const ServiceTestScreen({super.key, required this.service});
  final ServiceConfigDto service;

  @override
  Widget build(BuildContext context) {
    final svcList = [service];
    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.text2),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(service.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            Row(children: [
              _TypeBadge(type: service.type, small: true),
              const SizedBox(width: 6),
              Text(service.vendor,
                  style: const TextStyle(fontSize: 11, color: AppTheme.text2, fontWeight: FontWeight.w500)),
            ]),
          ],
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.text2),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => AddServiceModal(initialService: service),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: switch (service.type) {
          'stt' => _SttTestCard(services: svcList),
          'tts' => _TtsTestCard(services: svcList),
          'llm' => _LlmTestCard(services: svcList),
          'translation' => _TranslationTestCard(services: svcList),
          'sts' => _StsTestCard(services: svcList),
          'ast' => _AstTestCard(services: svcList),
          _ => Center(child: Text('暂无 ${service.type.toUpperCase()} 类型的测试',
              style: const TextStyle(color: AppTheme.text2))),
        },
      ),
    );
  }
}

// ── Type badge pill ──────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, this.small = false});
  final String type;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: _typeBg(type),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w700,
          color: _typeFg(type),
        ),
      ),
    );
  }
}

// ── Service card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});
  final ServiceConfigDto service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Extract masked key hint from configJson
    final cfg = _parseCfg(service.configJson);
    final hint = _buildHint(cfg);
    final isReady = cfg['_tested'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: type badge + status
            Row(
              children: [
                _TypeBadge(type: service.type, small: true),
                const Spacer(),
                Row(
                  children: [
                    Text('● ',
                        style: TextStyle(
                            fontSize: 8,
                            color: isReady ? AppTheme.success : AppTheme.warning)),
                    Text(
                      isReady ? '已就绪' : '未就绪',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isReady ? AppTheme.success : AppTheme.warning),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Service name
            Text(
              service.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Vendor · hint
            Text(
              hint,
              style: const TextStyle(fontSize: 10, color: AppTheme.text2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _parseCfg(String json) {
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }

  String _buildHint(Map<String, dynamic> cfg) {
    final vendor = _vendorName(service.vendor);
    // Try to show masked key or region
    final key = (cfg['apiKey'] ?? cfg['appKey'] ?? cfg['accessKeyId'] ?? '') as String;
    final region = cfg['region'] as String? ?? '';
    if (region.isNotEmpty && key.isNotEmpty) {
      return '$region · ${_mask(key)}';
    } else if (region.isNotEmpty) {
      return region;
    } else if (key.isNotEmpty) {
      return '$vendor · ${_mask(key)}';
    }
    return vendor;
  }

  String _mask(String s) {
    if (s.length <= 4) return '••••';
    return '••••${s.substring(s.length - 4)}';
  }

  String _vendorName(String vendor) => switch (vendor) {
        'openai' => 'OpenAI',
        'anthropic' => 'Anthropic',
        'google' => 'Google',
        'azure' => 'Azure',
        'aliyun' => '阿里云',
        'doubao' => '火山引擎',
        'deepseek' => 'DeepSeek',
        'tongyi' => '通义千问',
        'deepl' => 'DeepL',
        'remote' => '远程 MCP',
        _ => vendor,
      };
}

// ── Base test card shell ──────────────────────────────────────────────────────

class _TestCardShell extends StatelessWidget {
  const _TestCardShell({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.type,
    required this.child,
  });
  final String icon;
  final String title;
  final bool enabled;
  final String type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                const Spacer(),
                _TypeBadge(type: type, small: true),
              ],
            ),
            const SizedBox(height: 10),
            if (!enabled)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('暂无已配置的 ${_typeSectionLabel(type)} 服务',
                      style: const TextStyle(fontSize: 12, color: AppTheme.text2)),
                ),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

// ── STT test card ─────────────────────────────────────────────────────────────

class _SttTestCard extends StatefulWidget {
  const _SttTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_SttTestCard> createState() => _SttTestCardState();
}

class _SttTestCardState extends State<_SttTestCard> {
  ServiceConfigDto? _selected;
  bool _recording = false;
  String _result = '';
  String _partial = '';
  String? _error;

  SttAzurePluginDart? _stt;
  StreamSubscription<SttEvent>? _sttSub;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _sttSub?.cancel();
    _stt?.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _error = status.isPermanentlyDenied
          ? '麦克风权限被永久拒绝，请前往系统设置开启'
          : '需要麦克风权限才能录音');
      return;
    }
    setState(() { _recording = true; _error = null; _result = ''; _partial = ''; });
    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final region = cfg['region'] as String? ?? '';

      _sttSub?.cancel();
      await _stt?.dispose();
      _stt = SttAzurePluginDart();
      await _stt!.initialize(SttConfig(apiKey: apiKey, region: region, language: 'zh-CN'));

      _sttSub = _stt!.eventStream.listen((e) {
        if (!mounted) return;
        switch (e.type) {
          case SttEventType.partialResult:
            setState(() => _partial = e.text ?? '');
          case SttEventType.finalResult:
            setState(() { _result = e.text ?? ''; _partial = ''; });
          case SttEventType.error:
            setState(() { _error = e.errorMessage ?? e.errorCode ?? '识别错误'; _recording = false; });
          default:
            break;
        }
      });

      await _stt!.startListening();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _recording = false; });
    }
  }

  Future<void> _stopRecording() async {
    try { await _stt?.stopListening(); } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  void _onServiceChanged(String name) {
    _sttSub?.cancel();
    _stt?.dispose();
    _stt = null;
    setState(() {
      _selected = widget.services.firstWhere((s) => s.name == name);
      _recording = false; _result = ''; _partial = ''; _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🎙',
      title: 'STT 识别测试',
      enabled: enabled,
      type: 'stt',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceDropdown(
            value: _selected!.name,
            items: widget.services.map((s) => s.name).toList(),
            onChanged: _onServiceChanged,
          ),
          const SizedBox(height: 10),
          // Record button — long press to record
          Center(
            child: GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) { if (_recording) _stopRecording(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _recording ? 72 : 64,
                height: _recording ? 72 : 64,
                decoration: BoxDecoration(
                  color: _recording ? AppTheme.danger : AppTheme.success,
                  shape: BoxShape.circle,
                  boxShadow: _recording ? [BoxShadow(color: AppTheme.danger.withValues(alpha: 0.4), blurRadius: 16)] : null,
                ),
                child: Icon(
                  _recording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: _recording ? 32 : 28,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(child: Text(
            _recording ? '松开停止识别' : '长按开始录音',
            style: TextStyle(fontSize: 11, color: _recording ? AppTheme.danger : AppTheme.text2),
          )),
          if (_recording && _partial.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true, activeColor: AppTheme.warning,
              child: Text(_partial, style: const TextStyle(fontSize: 13, color: AppTheme.warning, height: 1.4)),
            ),
          ],
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true, activeColor: AppTheme.success,
              child: Text(_result, style: const TextStyle(fontSize: 13, color: AppTheme.text1, height: 1.5)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
            ]),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── TTS test card ─────────────────────────────────────────────────────────────

class _TtsTestCard extends StatefulWidget {
  const _TtsTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_TtsTestCard> createState() => _TtsTestCardState();
}

class _TtsTestCardState extends State<_TtsTestCard> {
  ServiceConfigDto? _selected;
  final _textCtrl = TextEditingController(text: '欢迎使用 AI Agent 测试平台！');
  bool _synthesizing = false;
  String? _result;
  String? _error;

  // Audio playback
  final _player = AudioPlayer();
  Uint8List? _audioBytes;
  bool _playing = false;

  // Voice list
  List<_VoiceInfo> _voices = [];
  String? _selectedVoice;
  bool _fetchingVoices = false;
  String? _voiceFetchError;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) {
      _selected = widget.services.first;
      _initVoice(_selected!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchVoices(_selected!);
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _initVoice(ServiceConfigDto s) {
    try {
      final cfg = jsonDecode(s.configJson) as Map;
      _selectedVoice = cfg['voiceName'] as String?;
    } catch (_) {}
  }

  Future<void> _fetchVoices(ServiceConfigDto s) async {
    if (s.vendor != 'azure') return;
    setState(() { _fetchingVoices = true; _voiceFetchError = null; });
    try {
      final cfg = jsonDecode(s.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final region = cfg['region'] as String? ?? '';
      if (apiKey.isEmpty || region.isEmpty) {
        setState(() => _voiceFetchError = 'apiKey 或 region 为空');
        return;
      }
      final resp = await http.get(
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/voices/list'),
        headers: {'Ocp-Apim-Subscription-Key': apiKey},
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final list = jsonDecode(resp.body) as List;
      if (!mounted) return;
      final voices = list.map((v) => _VoiceInfo(
        shortName: v['ShortName'] as String? ?? '',
        displayName: v['DisplayName'] as String? ?? '',
        locale: v['Locale'] as String? ?? '',
      )).toList();
      setState(() {
        _voices = voices;
        if (_selectedVoice == null || !_voices.any((v) => v.shortName == _selectedVoice)) {
          _selectedVoice = _voices.where((v) => v.locale.startsWith('zh')).firstOrNull?.shortName
              ?? _voices.firstOrNull?.shortName;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _voiceFetchError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _fetchingVoices = false);
    }
  }

  /// Call Azure TTS REST API to synthesize, then auto-play
  Future<void> _testSynthesize() async {
    if (_selected == null || _textCtrl.text.trim().isEmpty) return;
    setState(() { _synthesizing = true; _error = null; _result = null; _audioBytes = null; _playing = false; });
    await _player.stop();
    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final region = cfg['region'] as String? ?? '';
      final voice = _selectedVoice ?? 'zh-CN-XiaoxiaoNeural';
      final text = _textCtrl.text.trim();

      final ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
          "<voice name='$voice'>$text</voice></speak>";

      final resp = await http.post(
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/v1'),
        headers: {
          'Ocp-Apim-Subscription-Key': apiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
        },
        body: ssml,
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        _audioBytes = resp.bodyBytes;
        final kb = (_audioBytes!.length / 1024).toStringAsFixed(1);
        if (mounted) setState(() => _result = '合成成功 ${kb}KB · $voice');
        // Auto-play
        _playAudio();
      } else {
        throw Exception('HTTP ${resp.statusCode}：${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _synthesizing = false);
    }
  }

  Future<void> _playAudio() async {
    if (_audioBytes == null) return;
    setState(() => _playing = true);
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    await _player.play(BytesSource(_audioBytes!));
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (mounted) setState(() => _playing = false);
  }

  void _onServiceChanged(String name) {
    final s = widget.services.firstWhere((s) => s.name == name);
    setState(() {
      _selected = s;
      _voices = [];
      _selectedVoice = null;
      _voiceFetchError = null;
      _result = null;
      _error = null;
      _initVoice(s);
    });
    _fetchVoices(s);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🔊',
      title: 'TTS 合成测试',
      enabled: enabled,
      type: 'tts',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ServiceDropdown(
                  value: _selected!.name,
                  items: widget.services.map((s) => s.name).toList(),
                  onChanged: _onServiceChanged,
                ),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                label: _synthesizing ? '...' : '合成',
                color: AppTheme.primary,
                onTap: _synthesizing ? null : _testSynthesize,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Voice selector
          if (_fetchingVoices)
            const Row(children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 8),
              Text('获取音色列表...', style: TextStyle(fontSize: 11, color: AppTheme.text2)),
            ])
          else if (_voices.isNotEmpty)
            _ServiceDropdown(
              value: _selectedVoice ?? _voices.first.shortName,
              items: _voices.map((v) => v.shortName).toList(),
              onChanged: (v) => setState(() => _selectedVoice = v),
            )
          else if (_voiceFetchError != null)
            GestureDetector(
              onTap: () => _fetchVoices(_selected!),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 12, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_voiceFetchError!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
                const SizedBox(width: 4),
                const Text('重试', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ]),
            )
          else if (_selectedVoice != null)
            _InfoChip(label: _selectedVoice!),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: AppTheme.text1),
            decoration: InputDecoration(
              hintText: '输入要合成的文字...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
              filled: true, fillColor: AppTheme.bgColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          if (_synthesizing) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 8),
              Text('合成中...', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
            ]),
          ],
          if (_result != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
              const SizedBox(width: 6),
              Expanded(child: Text(_result!, style: const TextStyle(fontSize: 12, color: AppTheme.success))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _playing ? _stopAudio : _playAudio,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _playing ? AppTheme.danger : AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _playing ? Icons.stop : Icons.play_arrow,
                    color: Colors.white, size: 18,
                  ),
                ),
              ),
            ]),
            if (_playing) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(value: null, backgroundColor: AppTheme.borderColor, color: AppTheme.primary, minHeight: 3),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
            ]),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── LLM test card ─────────────────────────────────────────────────────────────

class _LlmTestCard extends StatefulWidget {
  const _LlmTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_LlmTestCard> createState() => _LlmTestCardState();
}

class _LlmTestCardState extends State<_LlmTestCard> {
  ServiceConfigDto? _selected;
  final _inputCtrl = TextEditingController(text: '你好，请介绍一下你自己');
  bool _sending = false;
  String _result = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_selected == null || _inputCtrl.text.trim().isEmpty) return;
    setState(() { _sending = true; _result = ''; _error = null; });

    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final vendor = _selected!.vendor;

      if (vendor == 'anthropic') {
        final baseUrl = cfg['baseUrl'] as String? ?? 'https://api.anthropic.com';
        final m = (cfg['model'] as String?)?.isNotEmpty == true
            ? cfg['model'] as String
            : 'claude-haiku-4-5-20251001';
        final resp = await http.post(
          Uri.parse('$baseUrl/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': m,
            'max_tokens': 512,
            'messages': [{'role': 'user', 'content': _inputCtrl.text.trim()}],
          }),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}：${_truncate(resp.body)}');
        final body = jsonDecode(resp.body) as Map;
        final content = (body['content'] as List).first as Map;
        setState(() => _result = content['text'] as String? ?? '');
      } else {
        // OpenAI-compatible: OpenAI / DeepSeek / 通义千问 / 火山引擎
        final subType = cfg['_subType'] as String? ?? 'model';
        final isDoubaoBot = vendor == 'doubao' && subType == 'bot';

        // Resolve model: for doubao bot use botId, others use model field
        final String m;
        if (isDoubaoBot) {
          m = (cfg['botId'] as String?)?.isNotEmpty == true ? cfg['botId'] as String : '';
        } else {
          m = (cfg['model'] as String?)?.isNotEmpty == true
              ? cfg['model'] as String
              : _defaultModel(vendor);
        }
        if (m.isEmpty) {
          throw Exception('未配置模型名称，请在服务配置中填写');
        }

        // Resolve baseUrl: doubao bot uses /bots path
        final String baseUrl;
        if ((cfg['baseUrl'] as String?)?.isNotEmpty == true) {
          baseUrl = cfg['baseUrl'] as String;
        } else if (isDoubaoBot) {
          baseUrl = 'https://ark.cn-beijing.volces.com/api/v3/bots';
        } else {
          baseUrl = _defaultBaseUrl(vendor);
        }

        // Normalize: strip trailing /chat/completions if user entered full URL
        var normalizedUrl = baseUrl;
        if (normalizedUrl.endsWith('/')) normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
        if (normalizedUrl.endsWith('/chat/completions')) {
          normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - '/chat/completions'.length);
        }

        final resp = await http.post(
          Uri.parse('$normalizedUrl/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': m,
            'max_tokens': 512,
            'messages': [{'role': 'user', 'content': _inputCtrl.text.trim()}],
          }),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}：${_truncate(resp.body)}');
        final body = jsonDecode(resp.body) as Map;
        final choices = body['choices'] as List;
        final msg = (choices.first as Map)['message'] as Map;
        setState(() => _result = msg['content'] as String? ?? '');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _truncate(String s) {
    final t = s.trim();
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }

  String _defaultBaseUrl(String vendor) => switch (vendor) {
        'deepseek' => 'https://api.deepseek.com/v1',
        'tongyi' => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'doubao' => 'https://ark.cn-beijing.volces.com/api/v3',
        'google' => 'https://generativelanguage.googleapis.com/v1beta/openai',
        _ => 'https://api.openai.com/v1',
      };

  String _defaultModel(String vendor) => switch (vendor) {
        'deepseek' => 'deepseek-chat',
        'tongyi' => 'qwen-max',
        'google' => 'gemini-2.0-flash',
        _ => 'gpt-4o',
      };

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🤖',
      title: 'LLM 对话测试',
      enabled: enabled,
      type: 'llm',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ServiceDropdown(
                  value: _selected!.name,
                  items: widget.services.map((s) => s.name).toList(),
                  onChanged: (v) => setState(() =>
                      _selected = widget.services.firstWhere((s) => s.name == v)),
                ),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                label: _sending ? '...' : '发送',
                color: AppTheme.primary,
                onTap: _sending ? null : _send,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _inputCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: AppTheme.text1),
            decoration: InputDecoration(
              hintText: '输入消息...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
              filled: true,
              fillColor: AppTheme.bgColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          if (_sending) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 8),
              Text('等待响应...', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
            ]),
          ],
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.primary,
              child: Text(_result, style: const TextStyle(fontSize: 12, color: AppTheme.text1, height: 1.5)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── Translation test card ────────────────────────────────────────────────────

class _TranslationTestCard extends StatefulWidget {
  const _TranslationTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_TranslationTestCard> createState() => _TranslationTestCardState();
}

class _TranslationTestCardState extends State<_TranslationTestCard> {
  ServiceConfigDto? _selected;
  final _inputCtrl = TextEditingController(text: 'Hello, how are you?');
  String _srcLang = 'EN';
  String _dstLang = 'ZH';
  bool _translating = false;
  String _result = '';
  String? _error;

  static const _langs = ['ZH', 'EN', 'JA', 'KO', 'FR', 'DE', 'ES', 'RU', 'AR'];

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _translate() async {
    if (_selected == null || _inputCtrl.text.trim().isEmpty) return;
    setState(() { _translating = true; _result = ''; _error = null; });

    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final vendor = _selected!.vendor;

      if (vendor == 'deepl') {
        final authKey = cfg['apiKey'] as String? ?? '';
        final isFree = authKey.endsWith(':fx');
        final baseUrl = isFree
            ? 'https://api-free.deepl.com/v2/translate'
            : 'https://api.deepl.com/v2/translate';
        final resp = await http.post(
          Uri.parse(baseUrl),
          headers: {'Authorization': 'DeepL-Auth-Key $authKey', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': [_inputCtrl.text.trim()],
            'source_lang': _srcLang == 'ZH' ? 'ZH' : _srcLang,
            'target_lang': _dstLang == 'ZH' ? 'ZH-HANS' : _dstLang,
          }),
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final body = jsonDecode(resp.body) as Map;
        final translations = body['translations'] as List;
        setState(() => _result = (translations.first as Map)['text'] as String? ?? '');
      } else {
        // Other vendors — placeholder
        await Future.delayed(const Duration(milliseconds: 600));
        setState(() => _result = '（${_selected!.vendor} 翻译插件对接后显示结果）');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🌐',
      title: '翻译测试',
      enabled: enabled,
      type: 'translation',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ServiceDropdown(
                  value: _selected!.name,
                  items: widget.services.map((s) => s.name).toList(),
                  onChanged: (v) => setState(() =>
                      _selected = widget.services.firstWhere((s) => s.name == v)),
                ),
              ),
              const SizedBox(width: 6),
              _LangChip(
                value: _srcLang,
                langs: _langs,
                onChanged: (v) => setState(() => _srcLang = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 14, color: AppTheme.text2),
              ),
              _LangChip(
                value: _dstLang,
                langs: _langs,
                onChanged: (v) => setState(() => _dstLang = v),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                label: _translating ? '...' : '翻译',
                color: AppTheme.translateAccent,
                onTap: _translating ? null : _translate,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _inputCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: AppTheme.text1),
            decoration: InputDecoration(
              hintText: '输入要翻译的文字...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
              filled: true,
              fillColor: AppTheme.bgColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.translateAccent, width: 1.5)),
            ),
          ),
          if (_translating) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.translateAccent)),
              SizedBox(width: 8),
              Text('翻译中...', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
            ]),
          ],
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.translateAccent,
              child: Text(_result, style: const TextStyle(fontSize: 12, color: AppTheme.text1, height: 1.5)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── STS test card ─────────────────────────────────────────────────────────────

enum _StsPhase { idle, connecting, connected, error }

class _TestChatMsg {
  _TestChatMsg(this.role, this.text);
  final String role; // 'user' | 'assistant'
  String text;
}

class _StsTestCard extends StatefulWidget {
  const _StsTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_StsTestCard> createState() => _StsTestCardState();
}

class _StsTestCardState extends State<_StsTestCard> {
  ServiceConfigDto? _selected;
  _StsPhase _phase = _StsPhase.idle;
  String _statusText = '';
  String? _error;
  String? _sessionId;
  final _chatMessages = <_TestChatMsg>[];
  StreamSubscription<AgentEvent>? _eventSub;
  final _bridge = AgentRuntimeBridge();

  static const _accent = Color(0xFF4A42D9);

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_sessionId != null) _bridge.stopSession(_sessionId!);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    final sid = 'sts_test_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _phase = _StsPhase.connecting;
      _statusText = '连接中...';
      _error = null;
      _chatMessages.clear();
      _sessionId = sid;
    });

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream
        .where((e) => e.sessionId == sid)
        .listen(_onEvent, onError: (e) {
      if (mounted) setState(() { _phase = _StsPhase.error; _error = e.toString(); });
    });

    try {
      final vendor = _selected!.vendor;
      await _bridge.startSession(AgentSessionConfig(
        sessionId: sid,
        agentId: 'sts_test',
        inputMode: 'text',
        sttPluginName: 'stt_$vendor',
        ttsPluginName: 'tts_$vendor',
        llmPluginName: 'llm_$vendor',
        stsPluginName: 'sts_$vendor',
        sttConfigJson: '{}',
        ttsConfigJson: '{}',
        llmConfigJson: '{}',
        stsConfigJson: _selected!.configJson,
      ));
      await _bridge.setInputMode(sid, 'call');
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _StsPhase.error;
          _error = e.toString().replaceFirst('Exception: ', '');
          _sessionId = null;
        });
      }
    }
  }

  void _onEvent(AgentEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case SessionStateEvent(:final state):
          switch (state) {
            case AgentSessionState.listening:
              _phase = _StsPhase.connected;
              _statusText = '正在聆听...';
            case AgentSessionState.llm:
              _phase = _StsPhase.connected;
              _statusText = 'AI 思考中...';
            case AgentSessionState.tts || AgentSessionState.playing:
              _phase = _StsPhase.connected;
              _statusText = 'AI 正在说话...';
            case AgentSessionState.error:
              _phase = _StsPhase.error;
              _statusText = '错误';
            default:
              if (_phase == _StsPhase.connecting) _phase = _StsPhase.connected;
              _statusText = '已连接';
          }
        case rt.SttEvent(:final kind, :final text):
          if (kind == SttEventKind.finalResult && (text ?? '').isNotEmpty) {
            _chatMessages.add(_TestChatMsg('user', text!));
          }
        case rt.LlmEvent(:final kind, :final textDelta, :final requestId):
          if (kind == LlmEventKind.firstToken && (textDelta ?? '').isNotEmpty) {
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'assistant' && m.text.endsWith('\u200B$requestId'));
            if (idx == -1) {
              _chatMessages.add(_TestChatMsg('assistant', '$textDelta\u200B$requestId'));
            } else {
              final raw = _chatMessages[idx].text;
              final marker = raw.lastIndexOf('\u200B');
              _chatMessages[idx].text = '${raw.substring(0, marker)}$textDelta\u200B$requestId';
            }
          } else if (kind == LlmEventKind.done) {
            // Strip requestId marker
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'assistant' && m.text.contains('\u200B'));
            if (idx != -1) {
              final raw = _chatMessages[idx].text;
              final marker = raw.lastIndexOf('\u200B');
              if (marker != -1) _chatMessages[idx].text = raw.substring(0, marker);
            }
          }
        case AgentErrorEvent(:final message):
          _phase = _StsPhase.error;
          _error = message;
        default:
          break;
      }
    });
  }

  String _displayText(_TestChatMsg m) {
    final t = m.text;
    final marker = t.lastIndexOf('\u200B');
    return marker == -1 ? t : t.substring(0, marker);
  }

  Future<void> _hangUp() async {
    _eventSub?.cancel();
    _eventSub = null;
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try { await _bridge.stopSession(sid); } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _phase = _StsPhase.idle;
        _statusText = '';
        _error = null;
        _chatMessages.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    final isActive = _phase != _StsPhase.idle;
    final isConnected = _phase == _StsPhase.connected;
    final isConnecting = _phase == _StsPhase.connecting;
    final isListening = isConnected && _statusText.contains('聆听');

    return _TestCardShell(
      icon: '📞',
      title: 'STS 语音对话测试',
      enabled: enabled,
      type: 'sts',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: _ServiceDropdown(
                value: _selected!.name,
                items: widget.services.map((s) => s.name).toList(),
                onChanged: isActive ? (_) {} : (v) => setState(() =>
                    _selected = widget.services.firstWhere((s) => s.name == v)),
              ),
            ),
            const SizedBox(width: 8),
            if (!isActive)
              _ActionBtn(label: '接通', color: _accent, onTap: _connect)
            else
              _ActionBtn(
                label: isConnecting ? '...' : '挂断',
                color: AppTheme.danger,
                onTap: isConnecting ? null : _hangUp,
              ),
          ]),
          if (isActive) ...[
            const SizedBox(height: 10),
            _ResultBox(
              active: true,
              activeColor: _phase == _StsPhase.error ? AppTheme.danger : _accent,
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF22C55E)
                        : isConnecting ? AppTheme.warning : AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isConnecting ? '正在建立连接...' : _statusText,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: _phase == _StsPhase.error ? AppTheme.danger : _accent,
                  ),
                )),
                if (isListening) _WaveIcon(),
              ]),
            ),
          ],
          // ── Chat messages ──
          if (_chatMessages.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                reverse: true,
                itemCount: _chatMessages.length,
                itemBuilder: (_, i) {
                  final m = _chatMessages[_chatMessages.length - 1 - i];
                  final isUser = m.role == 'user';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                      children: [
                        Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.55),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isUser ? _accent.withValues(alpha: 0.1) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _displayText(m),
                            style: TextStyle(
                              fontSize: 12,
                              color: isUser ? _accent : AppTheme.text1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_error!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── AST quick test card ──────────────────────────────────────────────────────

class _AstTestCard extends StatefulWidget {
  const _AstTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_AstTestCard> createState() => _AstTestCardState();
}

class _AstTestCardState extends State<_AstTestCard> {
  ServiceConfigDto? _selected;
  _StsPhase _phase = _StsPhase.idle;
  String _statusText = '';
  String? _error;
  String? _sessionId;
  final _chatMessages = <_TestChatMsg>[];
  StreamSubscription<AgentEvent>? _eventSub;
  final _bridge = AgentRuntimeBridge();

  String _srcLang = 'zh';
  String _dstLang = 'en';

  static const _accent = Color(0xFF9A3412);
  static const _langMap = {
    'zh': '中文', 'en': 'English', 'ja': '日本語', 'ko': '한국어',
    'fr': 'Français', 'de': 'Deutsch', 'es': 'Español',
    'ru': 'Русский', 'ar': 'العربية', 'pt': 'Português',
  };

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_sessionId != null) _bridge.stopSession(_sessionId!);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    final sid = 'ast_test_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _phase = _StsPhase.connecting;
      _statusText = '连接中...';
      _error = null;
      _chatMessages.clear();
      _sessionId = sid;
    });

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream
        .where((e) => e.sessionId == sid)
        .listen(_onEvent, onError: (e) {
      if (mounted) setState(() { _phase = _StsPhase.error; _error = e.toString(); });
    });

    try {
      final baseCfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      baseCfg['srcLang'] = _srcLang;
      baseCfg['dstLang'] = _dstLang;
      final mergedCfg = jsonEncode(baseCfg);

      final vendor = _selected!.vendor;
      await _bridge.startSession(AgentSessionConfig(
        sessionId: sid,
        agentId: 'ast_test',
        inputMode: 'text',
        sttPluginName: 'stt_$vendor',
        ttsPluginName: 'tts_$vendor',
        llmPluginName: 'llm_$vendor',
        stsPluginName: 'ast_$vendor',
        sttConfigJson: '{}',
        ttsConfigJson: '{}',
        llmConfigJson: '{}',
        stsConfigJson: mergedCfg,
      ));
      await _bridge.setInputMode(sid, 'call');
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _StsPhase.error;
          _error = e.toString().replaceFirst('Exception: ', '');
          _sessionId = null;
        });
      }
    }
  }

  void _onEvent(AgentEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case SessionStateEvent(:final state):
          switch (state) {
            case AgentSessionState.listening:
              _phase = _StsPhase.connected;
              _statusText = '正在聆听...';
            case AgentSessionState.llm:
              _phase = _StsPhase.connected;
              _statusText = '翻译中...';
            case AgentSessionState.tts || AgentSessionState.playing:
              _phase = _StsPhase.connected;
              _statusText = '正在播报译文...';
            case AgentSessionState.error:
              _phase = _StsPhase.error;
              _statusText = '错误';
            default:
              if (_phase == _StsPhase.connecting) _phase = _StsPhase.connected;
              _statusText = '已连接';
          }
        case rt.SttEvent(:final kind, :final text):
          if (kind == SttEventKind.finalResult && (text ?? '').isNotEmpty) {
            _chatMessages.add(_TestChatMsg('user', text!));
          }
        case rt.LlmEvent(:final kind, :final textDelta, :final requestId):
          if (kind == LlmEventKind.firstToken && (textDelta ?? '').isNotEmpty) {
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'assistant' && m.text.endsWith('\u200B$requestId'));
            if (idx == -1) {
              _chatMessages.add(_TestChatMsg('assistant', '$textDelta\u200B$requestId'));
            } else {
              final raw = _chatMessages[idx].text;
              final marker = raw.lastIndexOf('\u200B');
              _chatMessages[idx].text = '${raw.substring(0, marker)}$textDelta\u200B$requestId';
            }
          } else if (kind == LlmEventKind.done) {
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'assistant' && m.text.contains('\u200B'));
            if (idx != -1) {
              final raw = _chatMessages[idx].text;
              final marker = raw.lastIndexOf('\u200B');
              if (marker != -1) _chatMessages[idx].text = raw.substring(0, marker);
            }
          }
        case AgentErrorEvent(:final message):
          _phase = _StsPhase.error;
          _error = message;
        default:
          break;
      }
    });
  }

  String _displayText(_TestChatMsg m) {
    final t = m.text;
    final marker = t.lastIndexOf('\u200B');
    return marker == -1 ? t : t.substring(0, marker);
  }

  Future<void> _hangUp() async {
    _eventSub?.cancel();
    _eventSub = null;
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try { await _bridge.stopSession(sid); } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _phase = _StsPhase.idle;
        _statusText = '';
        _error = null;
        _chatMessages.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    final isActive = _phase != _StsPhase.idle;
    final isConnected = _phase == _StsPhase.connected;
    final isConnecting = _phase == _StsPhase.connecting;
    final isListening = isConnected && _statusText.contains('聆听');

    return _TestCardShell(
      icon: '🔄',
      title: 'AST 端到端翻译测试',
      enabled: enabled,
      type: 'ast',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Language pair: bigger pill buttons ──
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(child: _BigLangSelector(
                value: _srcLang, langMap: _langMap,
                enabled: !isActive,
                onChanged: (v) => setState(() => _srcLang = v),
              )),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 18, color: _accent),
              ),
              Expanded(child: _BigLangSelector(
                value: _dstLang, langMap: _langMap,
                enabled: !isActive,
                onChanged: (v) => setState(() => _dstLang = v),
              )),
            ]),
          ),
          Row(children: [
            Expanded(
              child: _ServiceDropdown(
                value: _selected!.name,
                items: widget.services.map((s) => s.name).toList(),
                onChanged: isActive ? (_) {} : (v) => setState(() =>
                    _selected = widget.services.firstWhere((s) => s.name == v)),
              ),
            ),
            const SizedBox(width: 8),
            if (!isActive)
              _ActionBtn(label: '接通', color: _accent, onTap: _connect)
            else
              _ActionBtn(
                label: isConnecting ? '...' : '挂断',
                color: AppTheme.danger,
                onTap: isConnecting ? null : _hangUp,
              ),
          ]),
          if (isActive) ...[
            const SizedBox(height: 10),
            _ResultBox(
              active: true,
              activeColor: _phase == _StsPhase.error ? AppTheme.danger : _accent,
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF22C55E)
                        : isConnecting ? AppTheme.warning : AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isConnecting ? '正在建立连接...' : _statusText,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: _phase == _StsPhase.error ? AppTheme.danger : _accent,
                  ),
                )),
                if (isListening) _WaveIcon(),
              ]),
            ),
          ],
          // ── Chat messages (bilingual pairs) ──
          if (_chatMessages.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                reverse: true,
                itemCount: _chatMessages.length,
                itemBuilder: (_, i) {
                  final m = _chatMessages[_chatMessages.length - 1 - i];
                  final isUser = m.role == 'user';
                  final langLabel = isUser
                      ? (_langMap[_srcLang] ?? _srcLang)
                      : (_langMap[_dstLang] ?? _dstLang);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isUser ? const Color(0xFFF9FAFB) : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isUser ? const Color(0xFFE5E7EB) : const Color(0xFFFED7AA),
                          width: 0.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(langLabel,
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: isUser ? AppTheme.text2 : _accent,
                            )),
                          const SizedBox(height: 2),
                          Text(
                            _displayText(m),
                            style: TextStyle(
                              fontSize: 13,
                              color: isUser ? AppTheme.text1 : _accent,
                              fontWeight: isUser ? FontWeight.w500 : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_error!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

/// Bigger language selector button with dropdown
class _BigLangSelector extends StatelessWidget {
  const _BigLangSelector({
    required this.value,
    required this.langMap,
    required this.enabled,
    required this.onChanged,
  });
  final String value;
  final Map<String, String> langMap;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFFFF7ED) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? const Color(0xFFF97316).withValues(alpha: 0.4) : AppTheme.borderColor,
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
          icon: Icon(Icons.keyboard_arrow_down, size: 16,
              color: enabled ? const Color(0xFF9A3412) : AppTheme.text2),
          onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
          items: langMap.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text('${e.value}  ${e.key}', overflow: TextOverflow.ellipsis),
          )).toList(),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _ServiceDropdown extends StatelessWidget {
  const _ServiceDropdown({required this.value, required this.items, required this.onChanged});
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 11, color: AppTheme.text1, fontWeight: FontWeight.w500),
          icon: const Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.text2),
          onChanged: (v) { if (v != null) onChanged(v); },
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.value, required this.langs, required this.onChanged});
  final String value;
  final List<String> langs;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 11, color: AppTheme.text1, fontWeight: FontWeight.w600),
          icon: const Icon(Icons.keyboard_arrow_down, size: 12, color: AppTheme.text2),
          onChanged: (v) { if (v != null) onChanged(v); },
          items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: onTap != null ? color : AppTheme.borderColor,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppTheme.text2),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({required this.active, required this.activeColor, required this.child});
  final bool active;
  final Color activeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.06) : AppTheme.bgColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: active ? activeColor.withValues(alpha: 0.4) : AppTheme.borderColor),
      ),
      child: child,
    );
  }
}

class _WaveIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => Container(
        width: 3,
        height: 6.0 + (i % 3) * 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: AppTheme.warning, borderRadius: BorderRadius.circular(2)),
      )),
    );
  }
}
