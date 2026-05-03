import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../models/translation_usage_stats.dart';
import '../models/meeting_usage_stats.dart';
import '../../core/utils/logger.dart';
import 'network/api.dart';
import '../models/goods.dart';
import '../models/user_Info.dart';

/// 使用量统计服务
///
class UsageStatsService extends GetxService {
  static const String _dailyStatsKey = 'daily_translation_stats';
  static const String _meetingDailyKey = 'daily_meeting_asr_stats';
  static const String _meetingOsDailykey = 'daily_meeting_os_stats';

  final GetStorage _storage = GetStorage();

  // 实时统计数据
  final Rx<RealtimeUsageStats> realtimeTranslationStats =
      RealtimeUsageStats().obs;

  // 当日统计数据
  final Rx<TranslationUsageStats> todayTranslationStats =
      TranslationUsageStats.empty('').obs;

  @override
  void onInit() {
    super.onInit();
    _initializeService();
  }

  /// 初始化服务
  void _initializeService() {
    _loadTodayTranslationStats();
    Logger.i('UsageStats', '使用量统计服务初始化完成');
  }

  /// 加载当日翻译统计数据
  void _loadTodayTranslationStats() {
    try {
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final statsData = _storage.read('${_dailyStatsKey}_$todayKey');
      if (statsData != null) {
        todayTranslationStats.value = TranslationUsageStats.fromJson(
            Map<String, dynamic>.from(statsData));
      } else {
        todayTranslationStats.value =
            TranslationUsageStats.empty(getCurrentUserId());
      }
    } catch (e) {
      Logger.error('加载当日翻译统计数据失败: $e');
      todayTranslationStats.value =
          TranslationUsageStats.empty(getCurrentUserId());
    }
  }

  /// 获取当前用户ID
  String getCurrentUserId() {
    try {
      final userInfo = _storage.read('user_info');
      if (userInfo != null && userInfo['user'] != null) {
        return userInfo['user']['uid'] ?? 'anonymous';
      }
    } catch (e) {
      Logger.warning('获取用户ID失败: $e');
    }
    return 'anonymous';
  }

  MeetingAsrDailyStats _loadMeetingDaily(String dateKey) {
    final data = _storage.read('${_meetingDailyKey}_$dateKey');
    if (data != null) {
      return MeetingAsrDailyStats.fromJson(Map<String, dynamic>.from(data));
    }
    return MeetingAsrDailyStats(
        date: dateKey, userId: getCurrentUserId(), items: []);
  }

  void _saveMeetingDaily(MeetingAsrDailyStats stats) {
    _storage.write('${_meetingDailyKey}_${stats.date}', stats.toJson());
    Logger.d('MeetingASRrecord',
        '保存会议当日统计: date=${stats.date}, items=${stats.items.length}');
  }

  String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// 记录单次对象存储上传
  /// [meetingId] 会议ID
  /// [storageUrl] 云端存储URL
  /// [storageBytes] 文件大小（字节）
  /// [transferBytes] 数据传输字节数
  /// [uploadTimestamp] 上传完成时间戳（毫秒）
  void recordMeetingObjectStorage({
    required int meetingId,
    required String storageUrl,
    required int storageBytes,
    required int transferBytes,
    required int uploadTimestamp,
  }) {
    final dateKey =
        _formatDate(DateTime.fromMillisecondsSinceEpoch(uploadTimestamp));
    final storageKey = '${_meetingOsDailykey}_$dateKey';

    final raw = _storage.read(storageKey);
    List<MeetingObjectStorageRecord> uploads = [];
    if (raw is List) {
      uploads = raw
          .map((e) =>
              MeetingObjectStorageRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    // final id = 'os_${uploadTimestamp}_${meetingId}';
    final record = MeetingObjectStorageRecord(
      meetingId: meetingId,
      storageUrl: storageUrl,
      storageBytes: storageBytes,
      transferBytes: transferBytes,
      uploadTimestamp: uploadTimestamp,
    );

    // 使用 meetingId + storageUrl 作为唯一标识来判断重复
    final exists = uploads.indexWhere(
            (e) => e.meetingId == meetingId && e.storageUrl == storageUrl) >=
        0;
    if (!exists) {
      uploads.add(record);
      _storage.write(storageKey, uploads.map((e) => e.toJson()).toList());
      Logger.d('MeetingOSrecord',
          '新增对象存储上传: meetingId=$meetingId, size=$storageBytes, transfer=$transferBytes');
    } else {
      Logger.d('MeetingOSrecord',
          '重复对象存储上传忽略: meetingId=$meetingId, url=$storageUrl');
    }
  }

  /// 添加或更新会议ASR记录
  /// [record] 会议ASR记录
  /// 该方法用于记录一次会议语音识别（ASR）的提交记录。它会根据记录的时间戳确定日期，
  /// 并将记录添加到该日期的会议ASR记录列表中。如果记录已存在，则会更新该记录。
  void addMeetingAsrRecord(MeetingAsrRecord record) {
    final dateKey = _formatDate(
        DateTime.fromMillisecondsSinceEpoch(record.submitTimestamp));
    final daily = _loadMeetingDaily(dateKey);
    final idx = daily.items.indexWhere((e) => e.id == record.id);
    if (idx >= 0) {
      daily.items[idx] = record;
      Logger.d('MeetingASRrecord',
          '更新会议ASR记录: id=${record.id}, meetingId=${record.meetingId}, date=${dateKey}');
    } else {
      daily.items.add(record);
      Logger.d('MeetingASRrecord',
          '新增会议ASR记录: id=${record.id}, meetingId=${record.meetingId}, date=${dateKey}');
    }
    _saveMeetingDaily(daily);
    Logger.i('MeetingASRrecord',
        '会议ASR提交: id=${record.id}, meetingId=${record.meetingId}, audioSeconds=${record.audioSeconds}, fileSizeBytes=${record.fileSizeBytes}, language=${record.language}, date=${dateKey}');
  }

  /// 完成会议ASR记录
  /// [id] 会议ASR记录ID
  /// [transcriptBytes] 转写结果文本字节数
  /// [completeTimestamp] 完成时间戳
  /// 该方法用于标记一次会议语音识别（ASR）任务为已完成状态。
  /// 它会根据记录ID在最近3天的会议ASR记录列表中查找匹配项，
  /// 如果找到，则更新该记录的状态为已完成，并记录转写结果文本字节数和完成时间戳。
  void completeMeetingAsrRecord({
    required String id,
    required int transcriptBytes,
    required int completeTimestamp,
  }) {
    final now = DateTime.now();
    for (int i = 0; i < 3; i++) {
      final dateKey = _formatDate(now.subtract(Duration(days: i)));
      final daily = _loadMeetingDaily(dateKey);
      final idx = daily.items.indexWhere((e) => e.id == id);
      if (idx >= 0) {
        final old = daily.items[idx];
        daily.items[idx] = MeetingAsrRecord(
          id: old.id,
          meetingId: old.meetingId,
          taskId: old.taskId,
          audioSeconds: old.audioSeconds,
          fileSizeBytes: old.fileSizeBytes,
          language: old.language,
          submitTimestamp: old.submitTimestamp,
          status: asrStatusCompleted,
          transcriptBytes: transcriptBytes,
          completeTimestamp: completeTimestamp,
        );
        _saveMeetingDaily(daily);
        Logger.i('MeetingASRrecord',
            '会议ASR完成: id=${id}, meetingId=${old.meetingId}, transcriptBytes=${transcriptBytes}, audioSeconds=${old.audioSeconds}, date=${dateKey}');
        try {
          _reportMeetingUsageToServer(
            audioSeconds: old.audioSeconds,
            audioBytes: old.fileSizeBytes,
            language: old.language,
            transcriptBytes: transcriptBytes,
          );
        } catch (e) {
          Logger.error('会议用量上报(完成)失败: $e');
        }
        return;
      }
    }
  }

  /// 上报会议用量到服务器
  /// [audioSeconds] 音频时长（秒）
  /// [audioBytes] 音频文件大小（字节）
  /// [language] 识别语言
  /// [transcriptBytes] 转写结果文本字节数（可选）
  /// 该方法用于将会议语音识别（ASR）的用量数据上报到服务器。
  /// 它会根据提供的参数构建一个包含会议用量类型、音频时长、音频文件大小、
  /// 识别语言以及可选的转写结果文本字节数的参数对象。
  /// 然后，它会调用API接口将该参数对象发送到服务器进行处理。
  /// 如果上报成功，服务器会返回一个响应，该方法会根据响应更新本地的用户积分（非总积分）。
  Future<void> _reportMeetingUsageToServer({
    required int audioSeconds,
    required int audioBytes,
    required String language,
    int? transcriptBytes,
  }) async {
    try {
      final params = {
        'usagetype': UsageType.Meet.toInt,
        'usages': {
          'MEETING_ASR_AUDIO_SECONDS': audioSeconds,
          // 'MEETING_ASR_AUDIO_BYTES': audioBytes,
          // if (transcriptBytes != null)
          //   'MEETING_ASR_TRANSCRIPT_BYTES': transcriptBytes,
          // 'MEETING_ASR_LANGUAGE_$language': 1,
        },
      };

      Logger.d('UsageStats', 'MEET用量上报参数: $params');

      final response = await Api.usagesResPoints(params);

      Logger.d('UsageStats', 'MEET用量上报响应: $response');

      _applyUsageResponse(response);
    } catch (e) {
      Logger.error('会议用量上报失败: $e');
    }
  }

  /// 记录翻译API调用
  void recordTranslationApiCall({
    required String sourceText,
    required String targetText,
    required String sourceLanguage,
    required String targetLanguage,
    required String mode,
  }) {
    try {
      // 更新实时统计
      realtimeTranslationStats.value.translationCount++;
      realtimeTranslationStats.value.sourceTextCharacters += sourceText.length;
      realtimeTranslationStats.value.ttsTextCharacters += targetText.length;
      realtimeTranslationStats.value.currentLanguagePair =
          '$sourceLanguage-$targetLanguage';
      realtimeTranslationStats.value.currentMode = mode;
      realtimeTranslationStats.refresh();

      // 更新当日统计 - 使用多维度统计
      final languagePair = '$sourceLanguage→$targetLanguage';

      // 更新语言对统计
      final newLanguagePairStats = Map<String, LanguagePairStats>.from(
          todayTranslationStats.value.languagePairStats);
      if (newLanguagePairStats.containsKey(languagePair)) {
        final existing = newLanguagePairStats[languagePair]!;
        newLanguagePairStats[languagePair] = LanguagePairStats(
          languagePair: languagePair,
          translationCount: existing.translationCount + 1,
          sourceCharacters: existing.sourceCharacters + sourceText.length,
        );
      } else {
        newLanguagePairStats[languagePair] = LanguagePairStats(
          languagePair: languagePair,
          translationCount: 1,
          sourceCharacters: sourceText.length,
        );
      }

      // 更新模式统计
      final newModeStats = Map<String, TranslationModeStats>.from(
          todayTranslationStats.value.modeStats);
      if (newModeStats.containsKey(mode)) {
        final existing = newModeStats[mode]!;
        newModeStats[mode] = existing.copyWith(
          apiCalls: existing.apiCalls + 1,
          sourceCharacters: existing.sourceCharacters + sourceText.length,
          ttsCharacters: existing.ttsCharacters + targetText.length,
        );
      } else {
        newModeStats[mode] = TranslationModeStats(
          apiCalls: 1,
          sourceCharacters: sourceText.length,
          ttsCharacters: targetText.length,
        );
      }

      todayTranslationStats.value = todayTranslationStats.value.copyWith(
        translationApiCalls:
            todayTranslationStats.value.translationApiCalls + 1,
        sourceTextCharacters: todayTranslationStats.value.sourceTextCharacters +
            sourceText.length,
        ttsTextCharacters:
            todayTranslationStats.value.ttsTextCharacters + targetText.length,
        languagePairStats: newLanguagePairStats,
        modeStats: newModeStats,
      );

      _saveTodayStats();

      Logger.info(
          '记录翻译API调用: 源文本${sourceText.length}字符, 目标文本${targetText.length}字符');
    } catch (e) {
      Logger.error('记录翻译API调用失败: $e');
    }
  }

  /// 记录ASR API调用 - 优化版（精确统计参数）
  void recordAsrApiCall({
    required int effectiveDurationSeconds, // 有效语音时长（VAD检测的实际语音）
    required int totalDurationSeconds, // 总会话时长（包含静音）
    required String language,
    required String mode, // 翻译模式
    String? audioFormat, // 音频格式（可选）
    int? sampleRate, // 采样率（可选）
  }) {
    try {
      // 更新实时统计（使用有效语音时长作为主要计费依据）
      realtimeTranslationStats.value.effectiveAudioDuration +=
          effectiveDurationSeconds;
      realtimeTranslationStats.value.totalSessionDuration +=
          totalDurationSeconds;
      realtimeTranslationStats.refresh();

      // 更新模式统计
      final newModeStats = Map<String, TranslationModeStats>.from(
          todayTranslationStats.value.modeStats);
      if (newModeStats.containsKey(mode)) {
        final existing = newModeStats[mode]!;
        newModeStats[mode] = existing.copyWith(
          effectiveAudioDuration:
              existing.effectiveAudioDuration + effectiveDurationSeconds,
        );
      } else {
        newModeStats[mode] = TranslationModeStats(
          effectiveAudioDuration: effectiveDurationSeconds,
        );
      }

      // 更新当日统计
      todayTranslationStats.value = todayTranslationStats.value.copyWith(
        asrApiCalls: todayTranslationStats.value.asrApiCalls + 1,
        effectiveAudioDuration:
            todayTranslationStats.value.effectiveAudioDuration +
                effectiveDurationSeconds,
        totalSessionDuration: todayTranslationStats.value.totalSessionDuration +
            totalDurationSeconds,
        modeStats: newModeStats,
      );

      _saveTodayStats();

      Logger.info(
          'ASR统计: 有效语音${effectiveDurationSeconds}秒, 总时长${totalDurationSeconds}秒, 语言$language, 模式$mode');
    } catch (e) {
      Logger.error('记录ASR API调用失败: $e');
    }

    _reportAsrUsageToServer(
      effectiveDurationSeconds: effectiveDurationSeconds,
      //totalDurationSeconds: totalDurationSeconds,
      language: language,
      mode: mode,
    );
  }

  /// 上报ASR用量到服务器
  /// [effectiveDurationSeconds] 有效语音时长（秒）
  /// [language] 识别语言
  /// [mode] 翻译模式
  /// 该方法用于将ASR（语音识别）的用量数据上报到服务器。
  /// 它会根据提供的参数构建一个包含用量类型、有效语音时长、识别语言以及翻译模式的参数对象。
  /// 然后，它会调用API接口将该参数对象发送到服务器进行处理。
  /// 如果上报成功，服务器会返回一个响应，该方法会根据响应更新本地的用户积分（非总积分）。
  Future<void> _reportAsrUsageToServer({
    required int effectiveDurationSeconds,
    //required int totalDurationSeconds,
    required String language,
    required String mode,
  }) async {
    try {
      final params = {
        'usagetype': UsageType.Translation.toInt,
        'usages': {
          // 'TRANSLATION_ASR_EFFECTIVE_SECONDS': effectiveDurationSeconds,
          //'TRANSLATION_ASR_TOTAL_SECONDS': totalDurationSeconds,
          'TRANSLATION_MODE_$mode': effectiveDurationSeconds,
          'TRANSLATION_ASR_LANGUAGE_$language': 1,
          // 'TRANSLATION_SOURCE_CHARACTERS':
          //     realtimeTranslationStats.value.sourceTextCharacters,
          // 'TRANSLATION_TARGET_CHARACTERS':
          //     realtimeTranslationStats.value.ttsTextCharacters,
        },
      };

      Logger.d('UsageStats', 'ASR用量上报参数: $params');

      final response = await Api.usagesResPoints(params);

      Logger.d('UsageStats', 'ASR用量上报响应: $response');

      _applyUsageResponse(response);
    } catch (e) {
      Logger.error('记录ASR API调用失败: $e');
    }
  }

  /// 根据服务器用量上报回应，更新用户积分（非总积分）
  /// 用量类型：0 AI聊天、1 翻译、2 会议
  void _applyUsageResponse(dynamic response) {
    try {
      if (response is! Map) return;
      final usagesObj = response['usages'];
      if (usagesObj is! Map) return;
      final usages = Map<String, dynamic>.from(usagesObj as Map);
      int _asInt(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v) ?? 0;
        return 0;
      }

      final Map<String, dynamic> update = {};
      usages.forEach((k, v) {
        final key = int.tryParse(k.toString());
        final val = _asInt(v);
        if (key == null) return;
        switch (key) {
          case 0:
            update['aichatintegral'] = val;
            break;
          case 1:
            update['tradeintegral'] = val;
            break;
          case 2:
            update['meetintegral'] = val;
            break;
        }
      });
      if (update.isNotEmpty) {
        User.instance.updateUserInfo(update);
        Logger.info('积分更新: $update');
      }
    } catch (e) {
      Logger.error('解析用量回应并更新积分失败: $e');
    }
  }

  /// 记录TTS API调用
  void recordTtsApiCall({
    required String text,
    required int durationSeconds,
    required String language,
  }) {
    try {
      // 更新实时统计
      realtimeTranslationStats.value.totalSessionDuration += durationSeconds;
      realtimeTranslationStats.refresh();

      // 更新当日统计（TTS按字符数计费，不是按时长）
      todayTranslationStats.value = todayTranslationStats.value.copyWith(
        ttsApiCalls: todayTranslationStats.value.ttsApiCalls + 1,
        ttsTextCharacters:
            todayTranslationStats.value.ttsTextCharacters + text.length,
        totalSessionDuration:
            todayTranslationStats.value.totalSessionDuration + durationSeconds,
      );

      _saveTodayStats();

      Logger.info('记录TTS API调用: 文本${text.length}字符, 时长${durationSeconds}秒');
    } catch (e) {
      Logger.error('记录TTS API调用失败: $e');
    }
  }

  /// 记录AI摘要API调用
  void recordAiSummaryApiCall() {
    try {
      // 更新当日统计
      todayTranslationStats.value = todayTranslationStats.value.copyWith(
        aiSummaryApiCalls: todayTranslationStats.value.aiSummaryApiCalls + 1,
      );

      _saveTodayStats();

      Logger.info('记录AI摘要API调用');
    } catch (e) {
      Logger.error('记录AI摘要API调用失败: $e');
    }
  }

  /// 开始新会话
  void startNewSession() {
    realtimeTranslationStats.value.reset();

    // 更新当日会话数
    todayTranslationStats.value = todayTranslationStats.value.copyWith(
      sessionCount: todayTranslationStats.value.sessionCount + 1,
    );

    _saveTodayStats();
    Logger.info('开始新的翻译会话');
  }

  /// 保存当日统计数据
  void _saveTodayStats() {
    try {
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      _storage.write(
          '${_dailyStatsKey}_$todayKey', todayTranslationStats.value.toJson());
    } catch (e) {
      Logger.error('保存当日统计数据失败: $e');
    }
  }

  /// 获取历史统计数据
  Future<List<TranslationUsageStats>> getHistoryStats({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final List<TranslationUsageStats> historyStats = [];

      for (DateTime date = startDate;
          date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
          date = date.add(const Duration(days: 1))) {
        final dateKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final statsData = _storage.read('${_dailyStatsKey}_$dateKey');

        if (statsData != null) {
          historyStats.add(TranslationUsageStats.fromJson(
              Map<String, dynamic>.from(statsData)));
        }
      }

      return historyStats;
    } catch (e) {
      Logger.error('获取历史统计数据失败: $e');
      return [];
    }
  }

  /// 清理过期数据（保留最近90天）
  void cleanupOldData() {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
      final allKeys = _storage.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_dailyStatsKey)) {
          final dateStr = key.replaceFirst('${_dailyStatsKey}_', '');
          try {
            final date = DateTime.parse(dateStr);
            if (date.isBefore(cutoffDate)) {
              _storage.remove(key);
              Logger.info('清理过期统计数据: $key');
            }
          } catch (e) {
            // 忽略解析错误的键
          }
        }
      }
    } catch (e) {
      Logger.error('清理过期数据失败: $e');
    }
  }

  /// 获取月度统计汇总
  Future<TranslationUsageStats> getMonthlyStats(int year, int month) async {
    try {
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0); // 月末

      final dailyStats = await getHistoryStats(
        startDate: startDate,
        endDate: endDate,
      );

      if (dailyStats.isEmpty) {
        return TranslationUsageStats.empty(getCurrentUserId());
      }

      // 汇总月度数据
      int totalTranslationCalls = 0;
      int totalAsrCalls = 0;
      int totalTtsCalls = 0;
      int totalAiSummaryCalls = 0;
      int totalSourceChars = 0;
      int totalTargetChars = 0;
      int totalRecordingDuration = 0;
      int totalTtsPlayDuration = 0;
      int totalSessions = 0;
      //double totalCost = 0.0;

      final Map<String, int> combinedLanguagePairUsage = {};
      final Map<String, int> combinedModeUsage = {};

      for (final stats in dailyStats) {
        totalTranslationCalls += stats.translationApiCalls;
        totalAsrCalls += stats.asrApiCalls;
        totalTtsCalls += stats.ttsApiCalls;
        totalAiSummaryCalls += stats.aiSummaryApiCalls;
        totalSourceChars += stats.sourceCharacterCount;
        totalTargetChars += stats.targetCharacterCount;
        totalRecordingDuration += stats.audioRecordingDuration;
        totalTtsPlayDuration += stats.ttsPlaybackDuration;
        totalSessions += stats.sessionCount;
        // totalCost += stats.estimatedCost;

        // 合并语言对使用统计
        stats.languagePairUsage.forEach((key, value) {
          combinedLanguagePairUsage[key] =
              (combinedLanguagePairUsage[key] ?? 0) + value;
        });

        // 合并模式使用统计
        stats.modeUsage.forEach((key, value) {
          combinedModeUsage[key] = (combinedModeUsage[key] ?? 0) + value;
        });
      }

      return TranslationUsageStats(
        id: 'monthly_${year}_$month',
        date: startDate,
        userId: getCurrentUserId(),
        timeGranularity: 'month',
        translationApiCalls: totalTranslationCalls,
        asrApiCalls: totalAsrCalls,
        ttsApiCalls: totalTtsCalls,
        aiSummaryApiCalls: totalAiSummaryCalls,
        sourceTextCharacters: totalSourceChars,
        effectiveAudioDuration: totalRecordingDuration,
        ttsTextCharacters: totalTargetChars,
        totalSessionDuration: totalTtsPlayDuration,
        sessionCount: totalSessions,
        // estimatedCost: totalCost,
      );
    } catch (e) {
      Logger.error('获取月度统计失败: $e');
      return TranslationUsageStats.empty(getCurrentUserId());
    }
  }

  /// 获取会议历史统计
  ///
  /// 从[startDate]到[endDate]的会议ASR记录。
  Future<List<MeetingAsrDailyStats>> getMeetingHistoryStats({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final List<MeetingAsrDailyStats> list = [];
      for (DateTime date = startDate;
          date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
          date = date.add(const Duration(days: 1))) {
        final key = _formatDate(date);
        final daily = _loadMeetingDaily(key);
        if (daily.items.isNotEmpty) {
          list.add(daily);
        }
      }
      Logger.i('MeetingASRrecord',
          '获取会议历史统计: start=${_formatDate(startDate)}, end=${_formatDate(endDate)}, 有效天数=${list.length}');
      return list;
    } catch (e) {
      Logger.error('获取会议历史统计失败: $e');
      return [];
    }
  }

  /// 聚合会议统计
  ///
  /// 从[daily]中聚合会议统计数据。
  MeetingAsrHistoryStats aggregateMeetingStats(
      List<MeetingAsrDailyStats> daily) {
    int calls = 0;
    int audioSeconds = 0;
    int audioBytes = 0;
    int transcriptBytes = 0;
    for (final d in daily) {
      calls += d.asrCalls;
      audioSeconds += d.audioSecondsTotal;
      audioBytes += d.audioBytesTotal;
      transcriptBytes += d.transcriptBytesTotal;
    }
    Logger.i('MeetingASRrecord',
        '聚合会议统计: calls=${calls}, audioSeconds=${audioSeconds}, audioBytes=${audioBytes}, transcriptBytes=${transcriptBytes}');
    return MeetingAsrHistoryStats(
      userId: getCurrentUserId(),
      allAsrCalls: calls,
      allAudioSeconds: audioSeconds,
      allAudioFileBytes: audioBytes,
      allTranscriptBytes: transcriptBytes,
    );
  }

  /// 获取会议对象存储历史统计
  ///
  /// 从[startDate]到[endDate]的会议对象存储上传记录。
  Future<List<MeetingStorageDailyStats>> getMeetingStorageHistoryStats({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final List<MeetingStorageDailyStats> list = [];
      for (DateTime date = startDate;
          date.isBefore(endDate) || date.isAtSameMomentAs(endDate);
          date = date.add(const Duration(days: 1))) {
        final key = _formatDate(date);
        final raw = _storage.read('${_meetingOsDailykey}_$key');
        List<MeetingObjectStorageRecord> uploads = [];
        if (raw is List) {
          uploads = raw
              .map((e) => MeetingObjectStorageRecord.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList();
        }
        if (uploads.isNotEmpty) {
          list.add(MeetingStorageDailyStats(
              date: key, userId: getCurrentUserId(), items: uploads));
        }
      }
      Logger.i('MeetingOSrecord',
          '获取会议对象存储历史: start=${_formatDate(startDate)}, end=${_formatDate(endDate)}, 有效天数=${list.length}');
      return list;
    } catch (e) {
      Logger.error('获取对象存储历史统计失败: $e');
      return [];
    }
  }

  MeetingStorageHistoryStats aggregateMeetingStorageStats(
      List<MeetingStorageDailyStats> daily) {
    int uploads = 0;
    int storageBytes = 0;
    int transferBytes = 0;
    for (final d in daily) {
      uploads += d.storageUploads;
      storageBytes += d.storageBytesTotal;
      transferBytes += d.transferBytesTotal;
    }
    Logger.i('MeetingOSrecord',
        '聚合对象存储统计: uploads=${uploads}, storageBytes=${storageBytes}, transferBytes=${transferBytes}');
    return MeetingStorageHistoryStats(
      userId: getCurrentUserId(),
      allStorageUploads: uploads,
      allStorageBytes: storageBytes,
      allTransferBytes: transferBytes,
    );
  }
}
