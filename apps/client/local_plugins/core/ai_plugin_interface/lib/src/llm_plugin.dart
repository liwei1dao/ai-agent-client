import 'dart:async';

import 'package:flutter/foundation.dart';

/// LLM 配置
class LlmConfig {
  const LlmConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    this.temperature = 0.7,
    this.maxTokens = 2048,
    this.systemPrompt,
    this.extraParams = const {},
    this.instructions = const [],
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final String? systemPrompt;
  final Map<String, dynamic> extraParams;

  /// 用户在 LLM 服务配置界面注册的"指令"——本质是 LLM 可见的 function call 占位。
  /// 调度层（agent_chat 等）会把它们当作 tool 传给 LLM；LLM 触发后调度层不再走
  /// MCP 执行链，而是派发 [LlmEventType.instructionTriggered] 给上层 UI/外设处理。
  final List<LlmInstructionDef> instructions;
}

/// 用户注册的"指令"占位定义。
///
/// 不携带任何实际执行逻辑——只是一个 LLM 可见的 function 名 + 描述（+ 可选参数 schema）。
/// 触发后由调度层派发事件，**真正的副作用**（播放下一曲、设备控制等）由
/// [InstructionHandlerRegistry] 中注册的处理器完成；未注册时只发事件不执行动作。
@immutable
class LlmInstructionDef {
  const LlmInstructionDef({
    required this.name,
    required this.description,
    this.parameters,
  });

  /// function 名（建议形如 `media.next_track`），LLM 会原样回填到 tool_call。
  final String name;

  /// 给 LLM 看的描述（决定何时触发，写清楚语义）。
  final String description;

  /// 可选 JSON Schema；为 null 时视为无参函数。
  final Map<String, dynamic>? parameters;

  /// 转为 LLM 可识别的 tool 定义。
  LlmTool toLlmTool() => LlmTool(
        name: name,
        description: description,
        parameters: parameters ??
            const {
              'type': 'object',
              'properties': <String, dynamic>{},
            },
      );

  factory LlmInstructionDef.fromJson(Map<String, dynamic> j) =>
      LlmInstructionDef(
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        parameters: j['parameters'] is Map
            ? (j['parameters'] as Map).cast<String, dynamic>()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        if (parameters != null) 'parameters': parameters,
      };
}

/// 指令处理器签名：拿到解析后的参数，返回 LLM 期望的"调用结果"字符串。
///
/// 返回 null 表示用户没注册副作用，调度层会回填一段默认 "ok" 文本给 LLM，
/// 让对话能继续；返回非空字符串则会原样作为 tool result 回灌到 LLM 历史。
typedef InstructionHandler = FutureOr<String?> Function(
  String name,
  Map<String, dynamic> args,
);

/// 全局指令处理器注册表。
///
/// 调度层（agent_chat / agent_sts_chat 等）会在派发 [LlmEventType.instructionTriggered]
/// 之后尝试 [dispatch] 同名 handler；底层 agent 对象只需在 app 启动期间
/// `InstructionHandlerRegistry.instance.register('media.next_track', ...)` 即可挂逻辑。
class InstructionHandlerRegistry {
  InstructionHandlerRegistry._();
  static final InstructionHandlerRegistry instance =
      InstructionHandlerRegistry._();

  final Map<String, InstructionHandler> _handlers = {};

  void register(String name, InstructionHandler handler) {
    _handlers[name] = handler;
  }

  void unregister(String name) => _handlers.remove(name);

  bool has(String name) => _handlers.containsKey(name);

  /// 找到对应 handler 并执行。无匹配时返回 null。
  Future<String?> dispatch(String name, Map<String, dynamic> args) async {
    final h = _handlers[name];
    if (h == null) return null;
    try {
      return await h(name, args);
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}

/// 聊天消息角色
enum MessageRole { system, user, assistant, tool }

/// 聊天消息
@immutable
class LlmMessage {
  const LlmMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.name,
    this.toolCalls,
  });

  final MessageRole role;

  /// 文本内容；assistant 在 tool_calls 阶段时可能为空
  final String content;

  /// tool 角色必填，关联到上一条 assistant 的 tool_calls[i].id
  final String? toolCallId;

  /// 可选名字（tool 角色为工具名）
  final String? name;

  /// assistant 角色可携带 tool_calls 列表（OpenAI 多轮 tool loop）
  final List<ToolCall>? toolCalls;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        // OpenAI 在 tool_calls 时允许 content=null；其它角色 content 必填
        if (toolCalls != null && toolCalls!.isNotEmpty && content.isEmpty)
          'content': null
        else
          'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (name != null) 'name': name,
        if (toolCalls != null && toolCalls!.isNotEmpty)
          'tool_calls': toolCalls!
              .map((c) => {
                    'id': c.id,
                    'type': 'function',
                    'function': {
                      'name': c.name,
                      'arguments': c.argumentsJson,
                    },
                  })
              .toList(),
      };
}

/// MCP / Function 工具定义
@immutable
class LlmTool {
  const LlmTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters; // JSON Schema

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// LLM 工具调用
@immutable
class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;
}

/// LLM 事件类型（8 种）
enum LlmEventType {
  /// 模型思考中（部分模型支持，如 o1）
  thinking,

  /// 第一个 token 到达（用于 UI 显示响应开始）
  firstToken,

  /// 工具调用开始（name 已知，arguments 流式中）
  toolCallStart,

  /// 工具调用参数片段（流式追加）
  toolCallArguments,

  /// 工具调用结果（执行完毕，结果回填）
  toolCallResult,

  /// LLM 完成
  done,

  /// 被取消（activeRequestId 不匹配）
  cancelled,

  /// 错误
  error,
}

/// LLM 事件
@immutable
class LlmEvent {
  const LlmEvent({
    required this.type,
    this.requestId,
    this.textDelta,
    this.thinkingDelta,
    this.toolCall,
    this.toolCalls,
    this.toolResult,
    this.fullText,
    this.errorCode,
    this.errorMessage,
  });

  final LlmEventType type;

  /// 对应的 requestId
  final String? requestId;

  /// 文本增量（firstToken / done 时的流式片段）
  final String? textDelta;

  /// 思考增量（thinking 类型）
  final String? thinkingDelta;

  /// 工具调用（toolCallStart 时单条）
  final ToolCall? toolCall;

  /// 完整工具调用列表（done 时携带；非空表示需要 chat 容器执行工具并多轮回灌）
  final List<ToolCall>? toolCalls;

  /// 工具调用结果文本（toolCallResult 时）
  final String? toolResult;

  /// 完整文本（done 时）
  final String? fullText;

  final String? errorCode;
  final String? errorMessage;
}

/// LLM 插件抽象接口
abstract class LlmPlugin {
  /// 初始化
  Future<void> initialize(LlmConfig config);

  /// 发起流式对话，返回事件流
  Stream<LlmEvent> chat({
    required String requestId,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
  });

  /// 取消当前请求
  void cancel(String requestId);

  /// 释放资源
  Future<void> dispose();
}
