/// 翻译模式统计数据
class TranslationModeStats {
  final int apiCalls; // API调用次数
  final int sourceCharacters; // 源文本字符数
  final int effectiveAudioDuration; // 有效音频时长
  final int ttsCharacters; // TTS字符数
  final double cost; // 成本

  TranslationModeStats({
    this.apiCalls = 0,
    this.sourceCharacters = 0,
    this.effectiveAudioDuration = 0,
    this.ttsCharacters = 0,
    this.cost = 0.0,
  });

  factory TranslationModeStats.fromJson(Map<String, dynamic> json) {
    return TranslationModeStats(
      apiCalls: json['apiCalls'] ?? 0,
      sourceCharacters: json['sourceCharacters'] ?? 0,
      effectiveAudioDuration: json['effectiveAudioDuration'] ?? 0,
      ttsCharacters: json['ttsCharacters'] ?? 0,
      cost: (json['cost'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiCalls': apiCalls,
      'sourceCharacters': sourceCharacters,
      'effectiveAudioDuration': effectiveAudioDuration,
      'ttsCharacters': ttsCharacters,
      'cost': cost,
    };
  }

  TranslationModeStats copyWith({
    int? apiCalls,
    int? sourceCharacters,
    int? effectiveAudioDuration,
    int? ttsCharacters,
    double? cost,
  }) {
    return TranslationModeStats(
      apiCalls: apiCalls ?? this.apiCalls,
      sourceCharacters: sourceCharacters ?? this.sourceCharacters,
      effectiveAudioDuration:
          effectiveAudioDuration ?? this.effectiveAudioDuration,
      ttsCharacters: ttsCharacters ?? this.ttsCharacters,
      cost: cost ?? this.cost,
    );
  }
}

/// 语言对统计数据
class LanguagePairStats {
  final String languagePair; // 语言对，如"zh-CN→en-US"
  final int translationCount; // 翻译次数
  final int sourceCharacters; // 源文本字符数
  final double cost; // 成本

  LanguagePairStats({
    required this.languagePair,
    this.translationCount = 0,
    this.sourceCharacters = 0,
    this.cost = 0.0,
  });

  factory LanguagePairStats.fromJson(Map<String, dynamic> json) {
    return LanguagePairStats(
      languagePair: json['languagePair'] ?? '',
      translationCount: json['translationCount'] ?? 0,
      sourceCharacters: json['sourceCharacters'] ?? 0,
      cost: (json['cost'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'languagePair': languagePair,
      'translationCount': translationCount,
      'sourceCharacters': sourceCharacters,
      'cost': cost,
    };
  }
}

/// 小时统计数据
class HourlyStats {
  final int hour; // 小时（0-23）
  final int apiCalls; // API调用次数
  final int sourceCharacters; // 源文本字符数
  final int effectiveAudioDuration; // 有效音频时长
  final double cost; // 成本

  HourlyStats({
    required this.hour,
    this.apiCalls = 0,
    this.sourceCharacters = 0,
    this.effectiveAudioDuration = 0,
    this.cost = 0.0,
  });

  factory HourlyStats.fromJson(Map<String, dynamic> json) {
    return HourlyStats(
      hour: json['hour'] ?? 0,
      apiCalls: json['apiCalls'] ?? 0,
      sourceCharacters: json['sourceCharacters'] ?? 0,
      effectiveAudioDuration: json['effectiveAudioDuration'] ?? 0,
      cost: (json['cost'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hour': hour,
      'apiCalls': apiCalls,
      'sourceCharacters': sourceCharacters,
      'effectiveAudioDuration': effectiveAudioDuration,
      'cost': cost,
    };
  }
}

/// 翻译使用统计数据模型 - 优化版
class TranslationUsageStats {
  // 基础信息
  final String id; // 统计记录ID
  final DateTime date; // 统计日期
  final String userId; // 用户ID
  final String timeGranularity; // 时间粒度：realtime/hour/day/week/month

  // API调用统计 - 精确化
  final int translationApiCalls; // 翻译API调用次数
  final int asrApiCalls; // ASR语音识别调用次数
  final int ttsApiCalls; // TTS语音合成调用次数
  final int aiSummaryApiCalls; // AI摘要生成调用次数（已废弃但保留兼容性）

  // 精确计费参数统计
  final int sourceTextCharacters; // 源文本字符数（翻译API计费基础）
  final int effectiveAudioDuration; // ASR有效语音时长（秒，ASR计费基础）
  final int ttsTextCharacters; // TTS文本字符数（TTS计费基础）
  final int totalSessionDuration; // 总会话时长（秒，用于分析）

  // 网络流量统计
  final int asrNetworkBytes; // ASR网络流量（字节）
  final int ttsNetworkBytes; // TTS网络流量（字节）
  final int translationNetworkBytes; // 翻译API网络流量（字节）

  // 多维度分类统计
  final int sessionCount; // 翻译会话数量
  final Map<String, TranslationModeStats> modeStats; // 按翻译模式分类统计
  final Map<String, LanguagePairStats> languagePairStats; // 按语言对分类统计
  final Map<String, HourlyStats> hourlyStats; // 按小时分类统计（仅日统计包含）

  // 成本相关
  final double estimatedCost; // 预估成本
  final String currency; // 货币单位
  final Map<String, double> costBreakdown; // 成本分解（ASR/TTS/Translation）

  TranslationUsageStats({
    required this.id,
    required this.date,
    required this.userId,
    this.timeGranularity = 'day',
    this.translationApiCalls = 0,
    this.asrApiCalls = 0,
    this.ttsApiCalls = 0,
    this.aiSummaryApiCalls = 0,
    this.sourceTextCharacters = 0,
    this.effectiveAudioDuration = 0,
    this.ttsTextCharacters = 0,
    this.totalSessionDuration = 0,
    this.asrNetworkBytes = 0,
    this.ttsNetworkBytes = 0,
    this.translationNetworkBytes = 0,
    this.sessionCount = 0,
    this.modeStats = const {},
    this.languagePairStats = const {},
    this.hourlyStats = const {},
    this.estimatedCost = 0.0,
    this.currency = 'CNY',
    this.costBreakdown = const {},
  });

  factory TranslationUsageStats.fromJson(Map<String, dynamic> json) {
    // 处理多维度统计数据的反序列化
    final modeStatsMap = <String, TranslationModeStats>{};
    if (json['modeStats'] != null) {
      final modeStatsJson = json['modeStats'] as Map<String, dynamic>;
      modeStatsJson.forEach((key, value) {
        modeStatsMap[key] = TranslationModeStats.fromJson(value);
      });
    }

    final languagePairStatsMap = <String, LanguagePairStats>{};
    if (json['languagePairStats'] != null) {
      final languagePairStatsJson =
          json['languagePairStats'] as Map<String, dynamic>;
      languagePairStatsJson.forEach((key, value) {
        languagePairStatsMap[key] = LanguagePairStats.fromJson(value);
      });
    }

    final hourlyStatsMap = <String, HourlyStats>{};
    if (json['hourlyStats'] != null) {
      final hourlyStatsJson = json['hourlyStats'] as Map<String, dynamic>;
      hourlyStatsJson.forEach((key, value) {
        hourlyStatsMap[key] = HourlyStats.fromJson(value);
      });
    }

    return TranslationUsageStats(
      id: json['id'] ?? '',
      date: DateTime.parse(json['date']),
      userId: json['userId'] ?? '',
      timeGranularity: json['timeGranularity'] ?? 'day',
      translationApiCalls: json['translationApiCalls'] ?? 0,
      asrApiCalls: json['asrApiCalls'] ?? 0,
      ttsApiCalls: json['ttsApiCalls'] ?? 0,
      aiSummaryApiCalls: json['aiSummaryApiCalls'] ?? 0,
      sourceTextCharacters: json['sourceTextCharacters'] ??
          json['sourceCharacterCount'] ??
          0, // 兼容旧字段
      effectiveAudioDuration: json['effectiveAudioDuration'] ??
          json['audioRecordingDuration'] ??
          0, // 兼容旧字段
      ttsTextCharacters: json['ttsTextCharacters'] ??
          json['targetCharacterCount'] ??
          0, // 兼容旧字段
      totalSessionDuration: json['totalSessionDuration'] ?? 0,
      asrNetworkBytes: json['asrNetworkBytes'] ?? 0,
      ttsNetworkBytes: json['ttsNetworkBytes'] ?? 0,
      translationNetworkBytes: json['translationNetworkBytes'] ?? 0,
      sessionCount: json['sessionCount'] ?? 0,
      modeStats: modeStatsMap,
      languagePairStats: languagePairStatsMap,
      hourlyStats: hourlyStatsMap,
      estimatedCost: (json['estimatedCost'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'CNY',
      costBreakdown: Map<String, double>.from(json['costBreakdown'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    // 序列化多维度统计数据
    final modeStatsJson = <String, dynamic>{};
    modeStats.forEach((key, value) {
      modeStatsJson[key] = value.toJson();
    });

    final languagePairStatsJson = <String, dynamic>{};
    languagePairStats.forEach((key, value) {
      languagePairStatsJson[key] = value.toJson();
    });

    final hourlyStatsJson = <String, dynamic>{};
    hourlyStats.forEach((key, value) {
      hourlyStatsJson[key] = value.toJson();
    });

    return {
      'id': id,
      'date': date.toIso8601String(),
      'userId': userId,
      'timeGranularity': timeGranularity,
      'translationApiCalls': translationApiCalls,
      'asrApiCalls': asrApiCalls,
      'ttsApiCalls': ttsApiCalls,
      'aiSummaryApiCalls': aiSummaryApiCalls,
      'sourceTextCharacters': sourceTextCharacters,
      'effectiveAudioDuration': effectiveAudioDuration,
      'ttsTextCharacters': ttsTextCharacters,
      'totalSessionDuration': totalSessionDuration,
      'asrNetworkBytes': asrNetworkBytes,
      'ttsNetworkBytes': ttsNetworkBytes,
      'translationNetworkBytes': translationNetworkBytes,
      'sessionCount': sessionCount,
      'modeStats': modeStatsJson,
      'languagePairStats': languagePairStatsJson,
      'hourlyStats': hourlyStatsJson,
      'estimatedCost': estimatedCost,
      'currency': currency,
      'costBreakdown': costBreakdown,
      // 保持向后兼容性
      'sourceCharacterCount': sourceTextCharacters,
      'targetCharacterCount': ttsTextCharacters,
      'audioRecordingDuration': effectiveAudioDuration,
      'ttsPlaybackDuration': totalSessionDuration,
    };
  }

  /// 创建空的统计记录
  factory TranslationUsageStats.empty(String userId) {
    return TranslationUsageStats(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      userId: userId,
    );
  }

  /// 复制并更新统计数据
  TranslationUsageStats copyWith({
    String? id,
    DateTime? date,
    String? userId,
    String? timeGranularity,
    int? translationApiCalls,
    int? asrApiCalls,
    int? ttsApiCalls,
    int? aiSummaryApiCalls,
    int? sourceTextCharacters,
    int? effectiveAudioDuration,
    int? ttsTextCharacters,
    int? totalSessionDuration,
    int? asrNetworkBytes,
    int? ttsNetworkBytes,
    int? translationNetworkBytes,
    int? sessionCount,
    Map<String, TranslationModeStats>? modeStats,
    Map<String, LanguagePairStats>? languagePairStats,
    Map<String, HourlyStats>? hourlyStats,
    double? estimatedCost,
    String? currency,
    Map<String, double>? costBreakdown,
  }) {
    return TranslationUsageStats(
      id: id ?? this.id,
      date: date ?? this.date,
      userId: userId ?? this.userId,
      timeGranularity: timeGranularity ?? this.timeGranularity,
      translationApiCalls: translationApiCalls ?? this.translationApiCalls,
      asrApiCalls: asrApiCalls ?? this.asrApiCalls,
      ttsApiCalls: ttsApiCalls ?? this.ttsApiCalls,
      aiSummaryApiCalls: aiSummaryApiCalls ?? this.aiSummaryApiCalls,
      sourceTextCharacters: sourceTextCharacters ?? this.sourceTextCharacters,
      effectiveAudioDuration:
          effectiveAudioDuration ?? this.effectiveAudioDuration,
      ttsTextCharacters: ttsTextCharacters ?? this.ttsTextCharacters,
      totalSessionDuration: totalSessionDuration ?? this.totalSessionDuration,
      asrNetworkBytes: asrNetworkBytes ?? this.asrNetworkBytes,
      ttsNetworkBytes: ttsNetworkBytes ?? this.ttsNetworkBytes,
      translationNetworkBytes:
          translationNetworkBytes ?? this.translationNetworkBytes,
      sessionCount: sessionCount ?? this.sessionCount,
      modeStats: modeStats ?? this.modeStats,
      languagePairStats: languagePairStats ?? this.languagePairStats,
      hourlyStats: hourlyStats ?? this.hourlyStats,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      currency: currency ?? this.currency,
      costBreakdown: costBreakdown ?? this.costBreakdown,
    );
  }

  /// 获取总API调用次数
  int get totalApiCalls =>
      translationApiCalls + asrApiCalls + ttsApiCalls + aiSummaryApiCalls;

  /// 获取总字符数（精确计费基础）
  int get totalCharacterCount => sourceTextCharacters + ttsTextCharacters;

  /// 获取总音频时长（包含有效时长和总会话时长）
  int get totalAudioDuration => effectiveAudioDuration + totalSessionDuration;

  /// 获取总网络流量
  int get totalNetworkBytes =>
      asrNetworkBytes + ttsNetworkBytes + translationNetworkBytes;

  /// 获取最常用的语言对
  String get mostUsedLanguagePair {
    if (languagePairStats.isEmpty) return 'null';
    return languagePairStats.entries
        .reduce((a, b) =>
            a.value.translationCount > b.value.translationCount ? a : b)
        .key;
  }

  /// 获取最常用的翻译模式
  String get mostUsedMode {
    if (modeStats.isEmpty) return 'null';
    return modeStats.entries
        .reduce((a, b) => a.value.apiCalls > b.value.apiCalls ? a : b)
        .key;
  }

  // 向后兼容性getter
  /// @deprecated 使用 sourceTextCharacters 替代
  int get sourceCharacterCount => sourceTextCharacters;

  /// @deprecated 使用 ttsTextCharacters 替代
  int get targetCharacterCount => ttsTextCharacters;

  /// @deprecated 使用 effectiveAudioDuration 替代
  int get audioRecordingDuration => effectiveAudioDuration;

  /// @deprecated 使用 totalSessionDuration 替代
  int get ttsPlaybackDuration => totalSessionDuration;

  /// @deprecated 使用 languagePairStats 替代
  Map<String, int> get languagePairUsage {
    final result = <String, int>{};
    languagePairStats.forEach((key, value) {
      result[key] = value.translationCount;
    });
    return result;
  }

  /// @deprecated 使用 modeStats 替代
  Map<String, int> get modeUsage {
    final result = <String, int>{};
    modeStats.forEach((key, value) {
      result[key] = value.apiCalls;
    });
    return result;
  }
}

/// 实时统计数据模型（用于当前会话）- 优化版
class RealtimeUsageStats {
  // 精确计费参数
  int translationCount = 0; // 当前会话翻译次数
  int sourceTextCharacters = 0; // 当前会话源文本字符数（翻译计费基础）
  int ttsTextCharacters = 0; // 当前会话TTS文本字符数（TTS计费基础）
  int effectiveAudioDuration = 0; // 当前会话有效语音时长（ASR计费基础）
  int totalSessionDuration = 0; // 当前会话总时长

  // 会话信息
  String currentLanguagePair = ''; // 当前语言对
  String currentMode = ''; // 当前翻译模式
  DateTime sessionStartTime = DateTime.now(); // 会话开始时间

  /// 重置统计数据
  void reset() {
    translationCount = 0;
    sourceTextCharacters = 0;
    ttsTextCharacters = 0;
    effectiveAudioDuration = 0;
    totalSessionDuration = 0;
    currentLanguagePair = '';
    currentMode = '';
    sessionStartTime = DateTime.now();
  }

  /// 获取会话持续时间（分钟）
  int get sessionDurationMinutes {
    return DateTime.now().difference(sessionStartTime).inMinutes;
  }

  // 向后兼容性getter
  /// @deprecated 使用 sourceTextCharacters 替代
  int get sourceCharacters => sourceTextCharacters;

  /// @deprecated 使用 ttsTextCharacters 替代
  int get targetCharacters => ttsTextCharacters;

  /// @deprecated 使用 effectiveAudioDuration 替代
  int get recordingDuration => effectiveAudioDuration;

  /// @deprecated 使用 totalSessionDuration 替代
  int get ttsPlayDuration => totalSessionDuration;
}
