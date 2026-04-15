import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:local_db/local_db.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/service_library_provider.dart';

// ── Type colors (shared with services_screen) ───────────────────────────────

Color _typeBg(String type) => switch (type) {
  'stt' => const Color(0xFFFEF3C7), 'tts' => const Color(0xFFF0FDF4),
  'llm' => const Color(0xFFFAF5FF), 'translation' => const Color(0xFFEFF6FF),
  'sts' => const Color(0xFFEEF0FF), 'ast' => const Color(0xFFFFF7ED),
  'mcp' => const Color(0xFFE8F5E9), _ => const Color(0xFFF3F4F6),
};

Color _typeFg(String type) => switch (type) {
  'stt' => const Color(0xFF92400E), 'tts' => const Color(0xFF14532D),
  'llm' => const Color(0xFF6B21A8), 'translation' => const Color(0xFF1D4ED8),
  'sts' => const Color(0xFF4A42D9), 'ast' => const Color(0xFF9A3412),
  'mcp' => const Color(0xFF1B5E20), _ => AppTheme.text2,
};

// ── Per-vendor config field definitions ─────────────────────────────────────

class _ConfigField {
  const _ConfigField(this.key, this.label, this.hint,
      {this.obscure = false, this.readonly = false, this.defaultValue});
  final String key;
  final String label;
  final String hint;
  final bool obscure;
  /// When true, shows as locked chip with edit toggle button
  final bool readonly;
  /// Pre-filled default value for readonly fields
  final String? defaultValue;
}

List<_ConfigField> _fieldsFor(String type, String vendor) {
  if (vendor == 'azure' && (type == 'stt' || type == 'tts')) {
    return const [
      _ConfigField('apiKey', 'API Key *', 'xxxxxxxxxxxxxxxxxxxxxxxx', obscure: true),
      _ConfigField('region', 'Region *', 'eastus'),
      // voiceName is handled by the voice picker after test-connect
    ];
  }
  if (vendor == 'aliyun') {
    return const [
      _ConfigField('appKey', 'AppKey *', 'xxxxxxxxxxxxxxxx'),
      _ConfigField('accessKeyId', 'AccessKey ID *', 'LTAI...', obscure: true),
      _ConfigField('accessKeySecret', 'AccessKey Secret *', 'xxxxxxxx', obscure: true),
    ];
  }
  if (vendor == 'google') {
    return const [
      _ConfigField('apiKey', 'API Key *', 'AIza...', obscure: true),
    ];
  }
  if (vendor == 'doubao') {
    if (type == 'ast') {
      return const [
        _ConfigField('appKey', 'App Key *', '2316081933'),
        _ConfigField('accessKey', 'Access Key *', 'xxxxxxxx', obscure: true),
        _ConfigField('resourceId', 'Resource ID *', 'volc.bigasr.auc',
            defaultValue: 'volc.bigasr.auc', readonly: true),
      ];
    }
    return [
      const _ConfigField('appId', 'App ID *', 'xxxxxxxx'),
      const _ConfigField('accessToken', 'Access Token *', 'xxxxxxxx', obscure: true),
      if (type == 'sts') const _ConfigField('appKey', 'App Key *', 'xxxxxxxxxxxxxxxx'),
      if (type == 'sts') const _ConfigField('voiceType', '音色 ID', 'BV700_V2_streaming'),
    ];
  }
  if (type == 'llm') {
    switch (vendor) {
      case 'openai':
        return const [
          _ConfigField('apiKey', 'API Key *', 'sk-proj-...', obscure: true),
          _ConfigField('baseUrl', 'Base URL（可选，用于代理）', 'https://api.openai.com/v1',
              readonly: true, defaultValue: 'https://api.openai.com/v1'),
          // model is handled by model picker after test-connect
        ];
      case 'anthropic':
        return const [
          _ConfigField('apiKey', 'API Key *', 'sk-ant-...', obscure: true),
          _ConfigField('baseUrl', 'Base URL（可选）', 'https://api.anthropic.com',
              readonly: true, defaultValue: 'https://api.anthropic.com'),
          _ConfigField('model', '默认 Model', 'claude-sonnet-4-20250514'),
        ];
      case 'tongyi':
        return const [
          _ConfigField('apiKey', 'API Key *', 'sk-...', obscure: true),
          _ConfigField('baseUrl', 'Base URL', 'https://dashscope.aliyuncs.com/compatible-mode/v1',
              readonly: true, defaultValue: 'https://dashscope.aliyuncs.com/compatible-mode/v1'),
          _ConfigField('model', '默认 Model *', 'qwen-max'),
        ];
      case 'deepseek':
        return const [
          _ConfigField('apiKey', 'API Key *', 'sk-...', obscure: true),
          _ConfigField('baseUrl', 'Base URL', 'https://api.deepseek.com/v1',
              readonly: true, defaultValue: 'https://api.deepseek.com/v1'),
          _ConfigField('model', '默认 Model', 'deepseek-chat'),
        ];
      case 'doubao':
        return const [
          _ConfigField('apiKey', 'API Key *', 'ARK API Key...', obscure: true),
          _ConfigField('model', '模型 / Endpoint *', 'ep-20241228xxxxxx 或 doubao-pro-32k'),
          _ConfigField('baseUrl', 'Base URL', 'https://ark.cn-beijing.volces.com/api/v3',
              readonly: true, defaultValue: 'https://ark.cn-beijing.volces.com/api/v3'),
        ];
      case 'google':
        return const [
          _ConfigField('apiKey', 'API Key *', 'AIza...', obscure: true),
          _ConfigField('baseUrl', 'Base URL', 'https://generativelanguage.googleapis.com/v1beta/openai',
              readonly: true, defaultValue: 'https://generativelanguage.googleapis.com/v1beta/openai'),
          _ConfigField('model', '默认 Model', 'gemini-2.0-flash'),
        ];
    }
  }
  if (vendor == 'polychat' && (type == 'sts' || type == 'ast')) {
    return const [
      _ConfigField('baseUrl', '服务器地址 *', 'https://your-polychat-server.com'),
      _ConfigField('appId', 'App ID *', 'app_xxxxxxxxxxxxxxxx'),
      _ConfigField('appSecret', 'App Secret *', 'xxxxxxxx', obscure: true),
    ];
  }
  if (vendor == 'deepl') {
    return const [
      _ConfigField('apiKey', 'Auth Key *', 'xxxxxxxx-xxxx-...', obscure: true),
    ];
  }
  if (type == 'mcp') {
    return const [
      _ConfigField('url', '服务地址 *', 'https://your-mcp-server.com/sse'),
      _ConfigField('transport', '传输协议', 'sse', defaultValue: 'sse'),
      _ConfigField('authHeader', '认证 Header（可选）', 'Bearer your-token'),
    ];
  }
  return const [_ConfigField('apiKey', 'API Key *', '...', obscure: true)];
}

// ── Voice item ──────────────────────────────────────────────────────────────

class _VoiceItem {
  _VoiceItem({required this.shortName, required this.displayName, required this.locale, required this.gender});
  final String shortName;
  final String displayName;
  final String locale;
  final String gender;
}

// ── Model item ──────────────────────────────────────────────────────────────

class _ModelItem {
  _ModelItem({required this.id});
  final String id;
}

// ── Type / vendor metadata ──────────────────────────────────────────────────

const _types = ['stt', 'tts', 'sts', 'ast', 'llm', 'translation', 'mcp'];
const _typeLabels = {'stt': 'STT', 'tts': 'TTS', 'sts': 'STS', 'ast': 'AST', 'llm': 'LLM', 'translation': '翻译', 'mcp': 'MCP'};
const _vendorsByType = <String, List<Map<String, String>>>{
  'stt': [
    {'id': 'azure', 'label': 'Azure'},
    {'id': 'aliyun', 'label': '阿里云'},
    {'id': 'google', 'label': 'Google'},
    {'id': 'doubao', 'label': '豆包'},
  ],
  'tts': [
    {'id': 'azure', 'label': 'Azure'},
    {'id': 'aliyun', 'label': '阿里云'},
    {'id': 'google', 'label': 'Google'},
    {'id': 'doubao', 'label': '豆包'},
  ],
  'llm': [
    {'id': 'openai', 'label': 'OpenAI'},
    {'id': 'anthropic', 'label': 'Anthropic'},
    {'id': 'google', 'label': 'Gemini'},
    {'id': 'tongyi', 'label': '通义千问'},
    {'id': 'deepseek', 'label': 'DeepSeek'},
    {'id': 'doubao', 'label': '火山引擎'},
  ],
  'sts': [
    {'id': 'doubao', 'label': '豆包'},
    {'id': 'polychat', 'label': 'PolyChat'},
  ],
  'ast': [
    {'id': 'doubao', 'label': '火山引擎'},
    {'id': 'polychat', 'label': 'PolyChat'},
  ],
  'translation': [
    {'id': 'deepl', 'label': 'DeepL'},
    {'id': 'aliyun', 'label': '阿里云'},
    {'id': 'google', 'label': 'Google'},
  ],
  'mcp': [
    {'id': 'remote', 'label': '远程 MCP'},
  ],
};

// ── Vendor doc/help info (registration URL + config hints) ──────────────────

class _VendorDoc {
  const _VendorDoc({required this.url, required this.urlLabel, required this.hint});
  final String url;       // Registration / console URL
  final String urlLabel;  // Button text
  final String hint;      // Config help text
}

const _vendorDocs = <String, Map<String, _VendorDoc>>{
  'azure': {
    'stt': _VendorDoc(
      url: 'https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices',
      urlLabel: 'Azure 语音服务控制台',
      hint: '创建"语音服务"资源后，在"密钥和终结点"页面获取 API Key 和 Region。',
    ),
    'tts': _VendorDoc(
      url: 'https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices',
      urlLabel: 'Azure 语音服务控制台',
      hint: '与 STT 共用同一个语音资源。填写 API Key 和 Region 后测试连接，可选择音色。',
    ),
  },
  'openai': {
    'llm': _VendorDoc(
      url: 'https://platform.openai.com/api-keys',
      urlLabel: 'OpenAI API Keys',
      hint: '在 API Keys 页面创建密钥。Base URL 默认即可，测试连接后选择模型。',
    ),
  },
  'anthropic': {
    'llm': _VendorDoc(
      url: 'https://console.anthropic.com/settings/keys',
      urlLabel: 'Anthropic Console',
      hint: '在 Settings → API Keys 创建密钥。推荐模型：claude-sonnet-4-20250514。',
    ),
  },
  'google': {
    'llm': _VendorDoc(
      url: 'https://aistudio.google.com/apikey',
      urlLabel: 'Google AI Studio',
      hint: '在 AI Studio 获取 API Key。推荐模型：gemini-2.0-flash。',
    ),
    'stt': _VendorDoc(
      url: 'https://console.cloud.google.com/speech',
      urlLabel: 'Google Cloud Speech',
      hint: '启用 Speech-to-Text API，在"凭据"页面创建 API Key。',
    ),
    'tts': _VendorDoc(
      url: 'https://console.cloud.google.com/speech',
      urlLabel: 'Google Cloud TTS',
      hint: '启用 Text-to-Speech API，在"凭据"页面创建 API Key。',
    ),
    'translation': _VendorDoc(
      url: 'https://console.cloud.google.com/translate',
      urlLabel: 'Google Cloud Translation',
      hint: '启用 Translation API，使用同一 API Key。',
    ),
  },
  'aliyun': {
    'stt': _VendorDoc(
      url: 'https://nls-portal.console.aliyun.com/overview',
      urlLabel: '阿里云智能语音控制台',
      hint: '创建项目后获取 AppKey。在 AccessKey 管理页获取 AccessKey ID 和 Secret。',
    ),
    'tts': _VendorDoc(
      url: 'https://nls-portal.console.aliyun.com/overview',
      urlLabel: '阿里云智能语音控制台',
      hint: '与 STT 共用项目。AppKey + AccessKey ID + Secret 三项必填。',
    ),
    'translation': _VendorDoc(
      url: 'https://mt.console.aliyun.com/',
      urlLabel: '阿里云机器翻译',
      hint: '开通机器翻译服务，使用 AccessKey 进行认证。',
    ),
  },
  'tongyi': {
    'llm': _VendorDoc(
      url: 'https://dashscope.console.aliyun.com/apiKey',
      urlLabel: '通义千问 DashScope',
      hint: '在 DashScope 控制台创建 API Key。推荐模型：qwen-max。',
    ),
  },
  'deepseek': {
    'llm': _VendorDoc(
      url: 'https://platform.deepseek.com/api_keys',
      urlLabel: 'DeepSeek Platform',
      hint: '在 API Keys 页面创建密钥。模型默认 deepseek-chat。',
    ),
  },
  'doubao': {
    'llm': _VendorDoc(
      url: 'https://console.volcengine.com/ark/region:ark+cn-beijing/endpoint',
      urlLabel: '火山方舟控制台',
      hint: '在"模型推理"创建推理接入点，获取 Endpoint ID（ep-xxx）。在"API Key管理"获取密钥。',
    ),
    'sts': _VendorDoc(
      url: 'https://console.volcengine.com/speech/app',
      urlLabel: '火山引擎语音控制台',
      hint: '创建应用获取 App ID 和 App Key。在"语音交互"开通 STS（语音转语音）能力。Access Token 在应用详情中获取。',
    ),
    'ast': _VendorDoc(
      url: 'https://console.volcengine.com/speech/app',
      urlLabel: '火山引擎语音控制台',
      hint: '创建应用获取 App Key。在"同传翻译"开通 AST 能力。Access Key 在"密钥管理"获取，Resource ID 默认 volc.bigasr.auc。',
    ),
    'stt': _VendorDoc(
      url: 'https://console.volcengine.com/speech/app',
      urlLabel: '火山引擎语音控制台',
      hint: '创建应用获取 App ID 和 Access Token。开通语音识别能力。',
    ),
    'tts': _VendorDoc(
      url: 'https://console.volcengine.com/speech/app',
      urlLabel: '火山引擎语音控制台',
      hint: '创建应用获取 App ID 和 Access Token。开通语音合成能力，选择音色 ID。',
    ),
  },
  'deepl': {
    'translation': _VendorDoc(
      url: 'https://www.deepl.com/your-account/keys',
      urlLabel: 'DeepL API Keys',
      hint: '注册 DeepL API Free 或 Pro 账户，在账户设置中获取 Auth Key。',
    ),
  },
  'remote': {
    'mcp': _VendorDoc(
      url: 'https://modelcontextprotocol.io/introduction',
      urlLabel: 'MCP 协议文档',
      hint: '填写 MCP 服务器地址（SSE 或 HTTP）。如需认证，填写 Auth Header（如 Bearer xxx）。',
    ),
  },
  'polychat': {
    'sts': _VendorDoc(
      url: '',
      urlLabel: 'PolyChat 控制台',
      hint: '填写 PolyChat 服务器地址、App ID 和 App Secret。每个 Agent 在平台同步时自动绑定。',
    ),
    'ast': _VendorDoc(
      url: '',
      urlLabel: 'PolyChat 控制台',
      hint: '填写 PolyChat 服务器地址、App ID 和 App Secret。每个 Agent 在平台同步时自动绑定。',
    ),
  },
};

_VendorDoc? _getVendorDoc(String vendor, String type) =>
    _vendorDocs[vendor]?[type];

/// Whether this (type, vendor) combo fetches a selectable resource list on test-connect.
/// STT only validates connectivity; TTS fetches voice list; LLM/OpenAI fetches model list.
bool _supportsFetch(String type, String vendor) {
  if (vendor == 'azure' && type == 'tts') return true;
  if (type == 'llm' && vendor == 'openai') return true;
  return false;
}

/// Services that don't need test — just save directly.
/// - MCP: no credentials to validate
/// - PolyChat STS/AST: platform credentials validated per-agent (agentId bound at Agent sync)
bool _skipTest(String type, [String vendor = '']) =>
    type == 'mcp' || vendor == 'polychat';

// ── Modal widget ────────────────────────────────────────────────────────────

class AddServiceModal extends ConsumerStatefulWidget {
  const AddServiceModal({super.key, this.initialService});

  /// When provided, the modal opens in edit mode pre-filled with existing data.
  final ServiceConfigDto? initialService;

  @override
  ConsumerState<AddServiceModal> createState() => _AddServiceModalState();
}

class _AddServiceModalState extends ConsumerState<AddServiceModal> {
  final _nameCtrl = TextEditingController();
  final _controllers = <String, TextEditingController>{};
  String _type = 'llm';
  String _vendor = 'openai';
  bool _saving = false;
  int _step = 0; // 0=选类型, 1=选服务商, 2=配置详情

  // Test-connect state
  bool _testing = false;
  bool _testOk = false;
  String? _testError;

  // Fetched resources
  List<_VoiceItem> _voices = [];
  String? _selectedVoice;
  String _voiceFilter = '';

  List<_ModelItem> _models = [];
  String? _selectedModel;

  final Set<String> _unlockedReadonly = {};

  /// 火山引擎 LLM 子类型: 'model'（模型推理） | 'bot'（应用接入）
  String _doubaoSubType = 'model';

  bool get _isEditing => widget.initialService != null;
  bool get _isDoubaoLlm => _type == 'llm' && _vendor == 'doubao';

  List<Map<String, String>> get _vendors => _vendorsByType[_type] ?? [];

  List<_ConfigField> get _fields {
    if (_isDoubaoLlm) {
      return const [
        _ConfigField('apiKey', 'API Key *', 'ARK API Key...', obscure: true),
        _ConfigField('model', 'Endpoint ID *', 'ep-20241228xxxxxx'),
        _ConfigField('baseUrl', 'Base URL *', 'https://ark.cn-beijing.volces.com/api/v3',
            readonly: true, defaultValue: 'https://ark.cn-beijing.volces.com/api/v3'),
        _ConfigField('temperature', 'Temperature', '0.7'),
        _ConfigField('maxTokens', 'Max Tokens', '2048'),
      ];
    }
    return _fieldsFor(_type, _vendor);
  }

  TextEditingController _ctrlFor(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    final s = widget.initialService;
    if (s != null) {
      _type = s.type;
      _vendor = s.vendor;
      _nameCtrl.text = s.name;
      _step = 2; // edit mode goes straight to config
      final config = jsonDecode(s.configJson) as Map<String, dynamic>;
      config.forEach((k, v) {
        if (k == 'voiceName') {
          _selectedVoice = v as String?;
        } else if (k == 'model' && _type != 'llm') {
          _selectedModel = v as String?;
        } else if (k == '_subType') {
          _doubaoSubType = v.toString();
        } else {
          _ctrlFor(k).text = v.toString();
        }
      });
    }
    _prefillDefaults();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _switchType(String t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _vendor = (_vendorsByType[t] ?? []).first['id']!;
      _resetTestState();
      _prefillDefaults();
    });
  }

  void _switchVendor(String v) {
    if (v == _vendor) return;
    setState(() {
      _vendor = v;
      _resetTestState();
      _prefillDefaults();
    });
  }

  void _resetTestState() {
    _testOk = false;
    _testError = null;
    _testing = false;
    _voices = [];
    _selectedVoice = null;
    _voiceFilter = '';
    _models = [];
    _selectedModel = null;
    _unlockedReadonly.clear();
    if (!_isDoubaoLlm) _doubaoSubType = 'model';
  }

  /// Pre-fill readonly fields with their defaultValue if the controller is empty.
  void _prefillDefaults() {
    for (final f in _fieldsFor(_type, _vendor)) {
      if (f.readonly && f.defaultValue != null) {
        final ctrl = _ctrlFor(f.key);
        if (ctrl.text.isEmpty) ctrl.text = f.defaultValue!;
      }
    }
  }

  // ── Test connect + fetch resources ────────────────────────────────────────

  Future<void> _testConnect() async {
    // Validate required fields first
    for (final f in _fields) {
      if (f.label.contains('*') && _ctrlFor(f.key).text.trim().isEmpty) {
        setState(() => _testError = '请先填写 ${f.label.replaceAll(' *', '')}');
        return;
      }
    }

    setState(() {
      _testing = true;
      _testOk = false;
      _testError = null;
    });

    try {
      if (_vendor == 'azure' && _type == 'tts') {
        await _fetchAzureVoices();
      } else if (_vendor == 'azure' && _type == 'stt') {
        await _testAzureSttConnection();
      } else if (_type == 'llm' && _vendor == 'openai') {
        await _fetchOpenAiModels();
      } else if (_type == 'llm') {
        await _testLlmApi();
      } else if ((_type == 'sts' || _type == 'ast') && _vendor == 'doubao') {
        await _testStsDoubaoConnection();
      } else {
        // MCP / Translation: no network test, just validate fields
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) setState(() => _testOk = true);
    } catch (e) {
      if (mounted) {
        setState(() => _testError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testAzureSttConnection() async {
    final apiKey = _ctrlFor('apiKey').text.trim();
    final region = _ctrlFor('region').text.trim();
    final url = Uri.parse(
        'https://$region.api.cognitive.microsoft.com/sts/v1.0/issueToken');
    final resp = await http.post(url, headers: {
      'Ocp-Apim-Subscription-Key': apiKey,
      'Content-Length': '0',
    }).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}：${resp.reasonPhrase}');
    }
    // Token received — credentials valid
  }

  /// 连接豆包 STS/AST WebSocket 验证凭证是否有效
  Future<void> _testStsDoubaoConnection() async {
    // AST 服务字段名与 STS 不同
    final appKey = _type == 'ast'
        ? _ctrlFor('appKey').text.trim()
        : _ctrlFor('appId').text.trim();
    final accessKey = _type == 'ast'
        ? _ctrlFor('accessKey').text.trim()
        : _ctrlFor('accessToken').text.trim();
    final resourceId = _type == 'ast'
        ? _ctrlFor('resourceId').text.trim()
        : 'volc.bigasr.auc';

    const wsUrl = 'wss://openspeech.bytedance.com/api/v4/ast/v2/translate';
    final connectId = DateTime.now().millisecondsSinceEpoch.toString();
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();

    final ws = await WebSocket.connect(wsUrl, headers: {
      'X-Api-App-Key': appKey,
      'X-Api-Access-Key': accessKey,
      'X-Api-Resource-Id': resourceId,
      'X-Api-Connect-Id': connectId,
    }).timeout(const Duration(seconds: 10),
        onTimeout: () => throw Exception('连接超时，请检查网络'));

    try {
      ws.add(_astBuildStartSession(sessionId));
      await for (final msg in ws.timeout(const Duration(seconds: 10),
          onTimeout: (sink) => sink.close())) {
        final bytes = msg is List ? Uint8List.fromList(msg.cast<int>()) : null;
        if (bytes == null) continue;
        final event = _astDecodeEvent(bytes);
        if (event == 150) return; // SessionStarted — credentials valid
        if (event == 153) {
          // SessionFailed — auth error
          throw Exception('认证失败，请检查 App ID 和 Access Token');
        }
      }
    } finally {
      ws.close().ignore();
    }
  }

  // ── Minimal Protobuf encoder for AST StartSession test ──────────────────

  List<int> _astVarint(int value) {
    final result = <int>[];
    while (value > 0x7F) {
      result.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    result.add(value);
    return result;
  }

  List<int> _astStr(int field, String value) {
    if (value.isEmpty) return [];
    final bytes = utf8.encode(value);
    return [..._astVarint((field << 3) | 2), ..._astVarint(bytes.length), ...bytes];
  }

  List<int> _astInt(int field, int value) {
    if (value == 0) return [];
    return [..._astVarint((field << 3) | 0), ..._astVarint(value)];
  }

  List<int> _astMsg(int field, List<int> msg) =>
      [..._astVarint((field << 3) | 2), ..._astVarint(msg.length), ...msg];

  Uint8List _astBuildStartSession(String sessionId) {
    final reqMeta  = _astMsg(1, _astStr(6, sessionId));
    final event    = _astInt(2, 100); // StartSession
    final user     = _astMsg(3, [..._astStr(1, 'ast_flutter'), ..._astStr(2, 'ast_flutter')]);
    final srcAudio = _astMsg(4, [
      ..._astStr(4, 'wav'), ..._astInt(7, 16000), ..._astInt(8, 16), ..._astInt(9, 1),
    ]);
    final dstAudio = _astMsg(5, [..._astStr(4, 'pcm_s16le'), ..._astInt(7, 24000)]);
    final reqParams = _astMsg(6, [
      ..._astStr(1, 's2s'), ..._astStr(2, 'zh'), ..._astStr(3, 'en'),
    ]);
    return Uint8List.fromList([...reqMeta, ...event, ...user, ...srcAudio, ...dstAudio, ...reqParams]);
  }

  int _astDecodeEvent(Uint8List bytes) {
    var pos = 0;
    while (pos < bytes.length) {
      var tag = 0; var shift = 0;
      while (pos < bytes.length) {
        final b = bytes[pos++];
        tag |= (b & 0x7F) << shift; shift += 7;
        if (b & 0x80 == 0) break;
      }
      final fieldNum = tag >> 3;
      final wireType = tag & 7;
      if (wireType == 0) {
        var v = 0; var sh = 0;
        while (pos < bytes.length) {
          final b = bytes[pos++];
          v |= (b & 0x7F) << sh; sh += 7;
          if (b & 0x80 == 0) break;
        }
        if (fieldNum == 2) return v;
      } else if (wireType == 2) {
        var len = 0; var sh = 0;
        while (pos < bytes.length) {
          final b = bytes[pos++];
          len |= (b & 0x7F) << sh; sh += 7;
          if (b & 0x80 == 0) break;
        }
        pos += len;
      } else if (wireType == 1) {
        pos += 8;
      } else if (wireType == 5) {
        pos += 4;
      } else {
        break;
      }
    }
    return 0;
  }

  Future<void> _fetchAzureVoices() async {
    final apiKey = _ctrlFor('apiKey').text.trim();
    final region = _ctrlFor('region').text.trim();
    final url = Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/voices/list');
    final resp = await http.get(url, headers: {'Ocp-Apim-Subscription-Key': apiKey}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}：${resp.reasonPhrase}');
    }
    final list = jsonDecode(resp.body) as List;
    _voices = list.map((v) => _VoiceItem(
      shortName: v['ShortName'] ?? '',
      displayName: v['DisplayName'] ?? '',
      locale: v['Locale'] ?? '',
      gender: v['Gender'] ?? '',
    )).toList();
    // Default select first Chinese voice
    _selectedVoice = _voices.where((v) => v.locale.startsWith('zh-')).firstOrNull?.shortName
        ?? _voices.firstOrNull?.shortName;
  }

  /// Real connectivity test for all non-OpenAI LLM vendors (sends a tiny request).
  Future<void> _testLlmApi() async {
    final apiKey = _ctrlFor('apiKey').text.trim();

    if (_vendor == 'anthropic') {
      final baseUrl = _ctrlFor('baseUrl').text.trim().isNotEmpty
          ? _ctrlFor('baseUrl').text.trim()
          : 'https://api.anthropic.com';
      final model = _ctrlFor('model').text.trim().isNotEmpty
          ? _ctrlFor('model').text.trim()
          : 'claude-haiku-4-5-20251001';
      final normalizedAnthropicUrl = _normalizeBaseUrl(baseUrl);
      final resp = await http.post(
        Uri.parse('$normalizedAnthropicUrl/v1/messages'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'max_tokens': 10,
          'messages': [{'role': 'user', 'content': 'hi'}],
        }),
      ).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}：${_shortBody(resp.body)}');
      }
      return;
    }

    // OpenAI-compatible: doubao / tongyi / deepseek / google / others
    final String baseUrl;
    final String model;

    if (_isDoubaoLlm) {
      if (_doubaoSubType == 'bot') {
        baseUrl = _ctrlFor('baseUrl').text.trim().isNotEmpty
            ? _ctrlFor('baseUrl').text.trim()
            : 'https://ark.cn-beijing.volces.com/api/v3/bots';
        model = _ctrlFor('botId').text.trim();
      } else {
        baseUrl = _ctrlFor('baseUrl').text.trim().isNotEmpty
            ? _ctrlFor('baseUrl').text.trim()
            : 'https://ark.cn-beijing.volces.com/api/v3';
        model = _ctrlFor('model').text.trim();
      }
    } else {
      baseUrl = _ctrlFor('baseUrl').text.trim().isNotEmpty
          ? _ctrlFor('baseUrl').text.trim()
          : _defaultLlmBaseUrl(_vendor);
      model = _ctrlFor('model').text.trim().isNotEmpty
          ? _ctrlFor('model').text.trim()
          : _defaultLlmModel(_vendor);
    }

    if (model.isEmpty) throw Exception('请先填写模型名称 / Endpoint ID');

    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final resp = await http.post(
      Uri.parse('$normalizedUrl/chat/completions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 10,
        'messages': [{'role': 'user', 'content': 'hi'}],
      }),
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}：${_shortBody(resp.body)}');
    }
  }

  String _defaultLlmBaseUrl(String vendor) => switch (vendor) {
        'tongyi' => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'deepseek' => 'https://api.deepseek.com/v1',
        'google' => 'https://generativelanguage.googleapis.com/v1beta/openai',
        'doubao' => 'https://ark.cn-beijing.volces.com/api/v3',
        _ => 'https://api.openai.com/v1',
      };

  String _defaultLlmModel(String vendor) => switch (vendor) {
        'tongyi' => 'qwen-max',
        'deepseek' => 'deepseek-chat',
        'google' => 'gemini-2.0-flash',
        _ => '',
      };

  /// Strip trailing /chat/completions or /v1/messages from user-entered baseUrl.
  String _normalizeBaseUrl(String url) {
    var u = url.trimRight();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    for (final suffix in ['/chat/completions', '/v1/messages']) {
      if (u.endsWith(suffix)) u = u.substring(0, u.length - suffix.length);
    }
    return u;
  }

  /// Truncate response body for error display.
  String _shortBody(String body) {
    final s = body.trim();
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  Future<void> _fetchOpenAiModels() async {
    final apiKey = _ctrlFor('apiKey').text.trim();
    final baseUrl = _ctrlFor('baseUrl').text.trim().isNotEmpty
        ? _ctrlFor('baseUrl').text.trim()
        : 'https://api.openai.com/v1';
    final url = Uri.parse('$baseUrl/models');
    final resp = await http.get(url, headers: {'Authorization': 'Bearer $apiKey'}).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}：${resp.reasonPhrase}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = body['data'] as List;
    _models = data.map((m) => _ModelItem(id: m['id'] ?? '')).toList();
    _models.sort((a, b) => a.id.compareTo(b.id));
    // Default select gpt-4o if available
    _selectedModel = _models.where((m) => m.id == 'gpt-4o').firstOrNull?.id
        ?? _models.firstOrNull?.id;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  String get _stepTitle => switch (_step) {
    0 => '选择服务类型',
    1 => '选择服务商',
    _ => _isEditing ? '编辑服务' : '配置服务',
  };

  @override
  Widget build(BuildContext context) {
    if (!_vendors.any((v) => v['id'] == _vendor)) {
      _vendor = _vendors.first['id']!;
    }
    final vendorLabel = _vendors.firstWhere((v) => v['id'] == _vendor)['label'] ?? '';
    final fields = _fields;
    final hasFetch = _supportsFetch(_type, _vendor);

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2))),
          ),
          // Header with back + title + step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                if (_step > 0 && !_isEditing)
                  GestureDetector(
                    onTap: () => setState(() { _step--; _resetTestState(); }),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(Icons.arrow_back_ios_new, size: 16, color: AppTheme.text2),
                    ),
                  ),
                Expanded(
                  child: Text(_stepTitle,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                ),
                if (!_isEditing)
                  // Step dots
                  Row(
                    children: List.generate(3, (i) => Container(
                      width: i == _step ? 16 : 6, height: 6,
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: i == _step ? AppTheme.primary : AppTheme.borderColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
                  ),
                if (_isEditing)
                  GestureDetector(
                    onTap: _handleDelete,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('删除', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.danger)),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Step content ──
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
              child: switch (_step) {
                // ═══ Step 0: 选择服务类型 ═══
                0 => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择你需要添加的服务类型',
                        style: TextStyle(fontSize: 13, color: AppTheme.text2)),
                    const SizedBox(height: 16),
                    ...(_types.map((t) {
                      final active = _type == t;
                      final emoji = switch (t) {
                        'stt' => '🎙', 'tts' => '🔊', 'llm' => '🧠',
                        'translation' => '🌐', 'sts' => '📞', 'ast' => '🔄', 'mcp' => '🔌', _ => '⚙️',
                      };
                      final desc = switch (t) {
                        'stt' => '语音识别 · 语音转文字',
                        'tts' => '语音合成 · 文字转语音',
                        'llm' => '大语言模型 · AI 对话',
                        'translation' => '文本翻译服务',
                        'sts' => '端到端语音对话（Speech-to-Speech）',
                        'ast' => '端到端同声传译（Audio-Speech-Translation）',
                        'mcp' => 'MCP 工具服务器',
                        _ => '',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _switchType(t);
                            _step = 1;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: active ? AppTheme.primaryLight : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active ? AppTheme.primary : AppTheme.borderColor,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(emoji, style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_typeLabels[t] ?? t, style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700,
                                      color: active ? AppTheme.primary : AppTheme.text1,
                                    )),
                                    const SizedBox(height: 2),
                                    Text(desc, style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
                                  ],
                                )),
                                Icon(Icons.chevron_right, size: 18,
                                    color: active ? AppTheme.primary : AppTheme.text2),
                              ],
                            ),
                          ),
                        ),
                      );
                    })),
                  ],
                ),

                // ═══ Step 1: 选择服务商 ═══
                1 => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 当前类型提示
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _typeBg(_type),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${_typeLabels[_type]} 服务',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _typeFg(_type))),
                    ),
                    const SizedBox(height: 16),
                    const Text('选择服务商', style: TextStyle(fontSize: 13, color: AppTheme.text2)),
                    const SizedBox(height: 12),
                    ..._vendors.map((v) {
                      final active = _vendor == v['id'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _switchVendor(v['id']!);
                            _step = 2;
                            if (_nameCtrl.text.isEmpty) {
                              _nameCtrl.text = '${v['label']} ${_typeLabels[_type]}';
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: active ? AppTheme.primaryLight : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active ? AppTheme.primary : AppTheme.borderColor,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Text(v['label']!, style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600,
                                  color: active ? AppTheme.primary : AppTheme.text1,
                                ))),
                                Icon(Icons.chevron_right, size: 18,
                                    color: active ? AppTheme.primary : AppTheme.text2),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),

                // ═══ Step 2: 配置详情 ═══
                _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 类型 + 服务商标签
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: _typeBg(_type), borderRadius: BorderRadius.circular(8)),
                        child: Text(_typeLabels[_type] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _typeFg(_type))),
                      ),
                      const SizedBox(width: 6),
                      Text(vendorLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.text1)),
                    ]),

                    // 配置说明文档入口
                    if (_getVendorDoc(_vendor, _type) != null) ...[
                      const SizedBox(height: 10),
                      _buildDocCard(_getVendorDoc(_vendor, _type)!),
                    ],

                    const SizedBox(height: 14),
                    _sectionLabel('服务名称'),
                    const SizedBox(height: 6),
                    _buildTextField(_nameCtrl, '我的 $vendorLabel'),
                    const SizedBox(height: 14),

                    // API 配置
                    _sectionLabel('API 配置'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppTheme.bgColor, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < fields.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _keyLabel(fields[i].label),
                            if (fields[i].readonly && !_unlockedReadonly.contains(fields[i].key))
                              _readonlyField(fields[i])
                            else
                              _keyField(_ctrlFor(fields[i].key), fields[i].hint, obscure: fields[i].obscure),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 测试连接
                    if (!_skipTest(_type, _vendor)) _buildTestButton(hasFetch),

                    // Error
                    if (_testError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppTheme.danger),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_testError!, style: const TextStyle(fontSize: 12, color: AppTheme.danger))),
                          ],
                        ),
                      ),
                    ],

                    // Voice picker
                    if (_testOk && _type == 'tts' && _voices.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildVoicePicker(),
                    ],

                    // Model picker
                    if (_testOk && _models.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _buildModelPicker(),
                    ],
                  ],
                ),
              },
            ),
          ),

          // ── Footer (only on step 2 / edit) ──
          if (_step == 2 || _isEditing) _buildFooter(context),
        ],
      ),
    );
  }

  // ── Test button ──

  Widget _buildTestButton(bool hasFetch) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: _testing ? null : _testConnect,
      icon: _testing
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(
              _testOk ? Icons.check_circle : Icons.power_outlined,
              size: 16,
              color: _testOk ? AppTheme.success : AppTheme.primary,
            ),
      label: Text(_testing
          ? '连接中...'
          : _testOk
              ? (hasFetch ? '连接成功 · 已获取列表' : '连接成功')
              : (hasFetch ? '测试连接并获取列表' : '测试连接')),
      style: OutlinedButton.styleFrom(
        foregroundColor: _testOk ? AppTheme.success : AppTheme.primary,
        side: BorderSide(color: _testOk ? AppTheme.success : AppTheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );

  // ── Voice picker (Azure) ──

  Widget _buildVoicePicker() {
    final filtered = _voiceFilter.isEmpty
        ? _voices
        : _voices.where((v) =>
            v.shortName.toLowerCase().contains(_voiceFilter.toLowerCase()) ||
            v.displayName.toLowerCase().contains(_voiceFilter.toLowerCase()) ||
            v.locale.toLowerCase().contains(_voiceFilter.toLowerCase())).toList();

    // Group by locale prefix
    final groups = <String, List<_VoiceItem>>{};
    for (final v in filtered) {
      final lang = v.locale.split('-').take(2).join('-');
      groups.putIfAbsent(lang, () => []).add(v);
    }
    // Put zh-CN / zh-* first, then en-*, then rest
    final sortedKeys = groups.keys.toList()..sort((a, b) {
      if (a.startsWith('zh') && !b.startsWith('zh')) return -1;
      if (!a.startsWith('zh') && b.startsWith('zh')) return 1;
      if (a.startsWith('en') && !b.startsWith('en')) return -1;
      if (!a.startsWith('en') && b.startsWith('en')) return 1;
      return a.compareTo(b);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel(_type == 'tts' ? '选择声音' : '可用语音列表'),
            const Spacer(),
            Text('${_voices.length} 个可用', style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
          ],
        ),
        const SizedBox(height: 8),
        // Search / filter
        TextField(
          onChanged: (v) => setState(() => _voiceFilter = v),
          style: const TextStyle(fontSize: 13, color: AppTheme.text1),
          decoration: InputDecoration(
            hintText: '搜索声音（语言、名称）...',
            hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
            prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.text2),
            filled: true, fillColor: AppTheme.bgColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            color: AppTheme.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: filtered.isEmpty
              ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('无匹配结果', style: TextStyle(color: AppTheme.text2, fontSize: 13))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: sortedKeys.length,
                  itemBuilder: (_, gi) {
                    final lang = sortedKeys[gi];
                    final voices = groups[lang]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(lang, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.text2, letterSpacing: 0.5)),
                        ),
                        for (final v in voices)
                          _VoiceTile(
                            voice: v,
                            selected: _selectedVoice == v.shortName,
                            onTap: () => setState(() => _selectedVoice = v.shortName),
                          ),
                      ],
                    );
                  },
                ),
        ),
        if (_selectedVoice != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
              const SizedBox(width: 4),
              Text('已选: $_selectedVoice',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.success)),
            ],
          ),
        ],
      ],
    );
  }

  // ── Model picker (OpenAI) ──

  Widget _buildModelPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _sectionLabel('选择模型'),
            const Spacer(),
            Text('${_models.length} 个可用', style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: AppTheme.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _models.length,
            itemBuilder: (_, i) {
              final m = _models[i];
              final selected = _selectedModel == m.id;
              return InkWell(
                onTap: () => setState(() => _selectedModel = m.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  color: selected ? AppTheme.primaryLight : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(m.id,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? AppTheme.primary : AppTheme.text1,
                          )),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Footer ──

  Widget _buildFooter(BuildContext context) => Container(
    decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.borderColor))),
    padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.text2,
              side: const BorderSide(color: AppTheme.borderColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('取消', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEditing ? '更新服务' : '保存服务', style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ),
  );

  // ── Helpers ──

  Widget _buildDocCard(_VendorDoc doc) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F7FF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFBFDBFE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: Color(0xFF1D4ED8)),
            const SizedBox(width: 6),
            const Text('配置说明', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1D4ED8))),
            const Spacer(),
            GestureDetector(
              onTap: () => _copyUrl(doc.url),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new, size: 10, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(doc.urlLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(doc.hint, style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF), height: 1.5)),
      ],
    ),
  );

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('链接已复制，请在浏览器中打开'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
      );
    }
  }

  Widget _sectionLabel(String text) => Text(text,
    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text2));

  Widget _buildTextField(TextEditingController ctrl, String hint) => TextField(
    controller: ctrl,
    style: const TextStyle(fontSize: 14, color: AppTheme.text1),
    decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: AppTheme.text2, fontSize: 13)),
  );

  Widget _keyLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.text2)),
  );

  Widget _readonlyField(_ConfigField f) {
    final value = _ctrlFor(f.key).text.isNotEmpty
        ? _ctrlFor(f.key).text
        : (f.defaultValue ?? f.hint);
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: AppTheme.text2, fontFamily: 'monospace'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _unlockedReadonly.add(f.key)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('修改',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
          ),
        ),
      ],
    );
  }

  Widget _keyField(TextEditingController ctrl, String hint, {bool obscure = false}) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: const TextStyle(fontSize: 13, color: AppTheme.text1),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.text2, fontSize: 12),
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
    ),
  );

  Future<void> _handleDelete() async {
    final id = widget.initialService?.id;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务'),
        content: const Text('确定要删除这个服务吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ref.read(serviceLibraryProvider.notifier).removeService(id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _testError = '请输入服务名称');
      return;
    }
    for (final f in _fields) {
      if (f.label.contains('*') && _ctrlFor(f.key).text.trim().isEmpty) {
        setState(() => _testError = '请填写 ${f.label.replaceAll(' *', '')}');
        return;
      }
    }

    setState(() { _saving = true; _testError = null; });

    try {
      final config = <String, dynamic>{};
      for (final f in _fields) {
        final val = _ctrlFor(f.key).text.trim();
        if (val.isNotEmpty) config[f.key] = val;
      }
      if (_selectedVoice != null) config['voiceName'] = _selectedVoice;
      if (_selectedModel != null) config['model'] = _selectedModel;
      if (_isDoubaoLlm) config['_subType'] = _doubaoSubType;
      if (_testOk || _skipTest(_type, _vendor)) config['_tested'] = true;

      final notifier = ref.read(serviceLibraryProvider.notifier);
      if (_isEditing) {
        await notifier.updateService(
          id: widget.initialService!.id,
          type: _type, vendor: _vendor, name: name, config: config,
        );
      } else {
        await notifier.addService(
          type: _type, vendor: _vendor, name: name, config: config,
        );
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _testError = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Voice tile widget ───────────────────────────────────────────────────────

class _VoiceTile extends StatelessWidget {
  const _VoiceTile({required this.voice, required this.selected, required this.onTap});
  final _VoiceItem voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected ? AppTheme.primaryLight : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(voice.shortName,
                    style: TextStyle(
                      fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppTheme.primary : AppTheme.text1)),
                  Text('${voice.displayName} · ${voice.gender}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.text2)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}
