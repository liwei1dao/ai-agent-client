///会议模块用量统计的模型类

// ============== ASR 状态常量 ==============
const int asrStatusProcessing = 0; // 处理中
const int asrStatusFailed = 1; // 处理失败
const int asrStatusCompleted = 2; // 已完成

// ============== ASR 单次记录 ==============
// 会议音频文件转文字单次数据
class MeetingAsrRecord {
  String id; // 本次ASR唯一标识
  int meetingId; // 会议记录ID
  String taskId; // 云端任务ID
  int audioSeconds; // 音频总时长(秒)
  int fileSizeBytes; // 音频文件大小(字节)
  String language; // ASR语言
  int submitTimestamp; // 提交时间戳(毫秒)

  int status; // 状态: 0-处理中, 1-处理失败, 2-已完成
  int transcriptBytes; // 转写后的字节数(utf8)
  int completeTimestamp; // 完成时间戳(毫秒)

  MeetingAsrRecord({
    required this.id,
    required this.meetingId,
    required this.taskId,
    required this.audioSeconds,
    required this.fileSizeBytes,
    required this.language,
    required this.submitTimestamp,
    required this.status,
    required this.transcriptBytes,
    required this.completeTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'meetingId': meetingId,
        'taskId': taskId,
        'audioSeconds': audioSeconds,
        'fileSizeBytes': fileSizeBytes,
        'language': language,
        'submitTimestamp': submitTimestamp,
        'status': status,
        'transcriptBytes': transcriptBytes,
        'completeTimestamp': completeTimestamp,
      };

  factory MeetingAsrRecord.fromJson(Map<String, dynamic> json) {
    return MeetingAsrRecord(
      id: json['id'] ?? '',
      meetingId: json['meetingId'] ?? 0,
      taskId: json['taskId'] ?? '',
      audioSeconds: json['audioSeconds'] ?? 0,
      fileSizeBytes: json['fileSizeBytes'] ?? 0,
      language: json['language'] ?? '',
      submitTimestamp: json['submitTimestamp'] ?? 0,
      status: json['status'] ?? 0,
      transcriptBytes: json['transcriptBytes'] ?? 0,
      completeTimestamp: json['completeTimestamp'] ?? 0,
    );
  }
}

// ============== 对象存储单次记录 ==============
// 对象存储单次上传记录
class MeetingObjectStorageRecord {
  int meetingId; // 会议记录ID
  String storageUrl; // 云端存储URL
  int storageBytes; // 文件大小(字节)
  int transferBytes; // 实际传输字节数
  int uploadTimestamp; // 上传完成时间戳(毫秒)

  MeetingObjectStorageRecord({
    required this.meetingId,
    required this.storageUrl,
    required this.storageBytes,
    required this.transferBytes,
    required this.uploadTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'meetingId': meetingId,
        'storageUrl': storageUrl,
        'storageBytes': storageBytes,
        'transferBytes': transferBytes,
        'uploadTimestamp': uploadTimestamp,
      };

  factory MeetingObjectStorageRecord.fromJson(Map<String, dynamic> json) {
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return MeetingObjectStorageRecord(
      meetingId: _asInt(json['meetingId']),
      storageUrl: (json['storageUrl'] ?? '').toString(),
      storageBytes: _asInt(json['storageBytes']),
      transferBytes: _asInt(json['transferBytes']),
      uploadTimestamp: _asInt(json['uploadTimestamp']),
    );
  }
}

// 会议音频文件转文字单日统计
class MeetingAsrDailyStats {
  String date; // 日期字符串: YYYY-MM-DD
  String userId; // 用户ID
  List<MeetingAsrRecord> items; // 当天所有单次ASR

  MeetingAsrDailyStats({
    required this.date,
    required this.userId,
    required this.items,
  });

  // 计算型聚合，不冗余存储
  int get asrCalls => items.length;
  int get audioSecondsTotal => items.fold(0, (s, r) => s + r.audioSeconds);
  int get audioBytesTotal => items.fold(0, (s, r) => s + r.fileSizeBytes);
  int get transcriptBytesTotal =>
      items.fold(0, (s, r) => s + r.transcriptBytes);

  Map<String, dynamic> toJson() => {
        'date': date,
        'userId': userId,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory MeetingAsrDailyStats.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List? ?? [])
        .map((e) => MeetingAsrRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return MeetingAsrDailyStats(
      date: json['date'] ?? '',
      userId: json['userId'] ?? 'anonymous',
      items: list,
    );
  }
}

// ============== 对象存储单日统计 ==============
// 👇 职责单一：仅统计对象存储相关数据
class MeetingStorageDailyStats {
  String date; // 日期字符串: YYYY-MM-DD
  String userId; // 用户ID
  List<MeetingObjectStorageRecord> items; // 当天所有单次对象存储记录

  MeetingStorageDailyStats({
    required this.date,
    required this.userId,
    required this.items,
  });

  // 对象存储 聚合计算
  int get storageUploads => items.length;
  int get storageBytesTotal => items.fold(0, (s, r) => s + r.storageBytes);
  int get transferBytesTotal => items.fold(0, (s, r) => s + r.transferBytes);

  Map<String, dynamic> toJson() => {
        'date': date,
        'userId': userId,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory MeetingStorageDailyStats.fromJson(Map<String, dynamic> json) {
    final storageList = (json['items'] as List? ?? [])
        .map((e) =>
            MeetingObjectStorageRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return MeetingStorageDailyStats(
      date: json['date'] ?? '',
      userId: json['userId'] ?? 'anonymous',
      items: storageList,
    );
  }
}

// 会议音频文件转文字历史统计（所有的用量）
class MeetingAsrHistoryStats {
  String userId; // 用户ID
  int allAsrCalls; // 所有ASR调用次数
  int allAudioSeconds; // 所有音频总时长(秒)
  int allAudioFileBytes; // 所有音频文件大小(字节)
  int allTranscriptBytes; // 所有转写后的字节数(utf8)

  MeetingAsrHistoryStats({
    required this.userId,
    required this.allAsrCalls,
    required this.allAudioSeconds,
    required this.allAudioFileBytes,
    required this.allTranscriptBytes,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'allAsrCalls': allAsrCalls,
        'allAudioSeconds': allAudioSeconds,
        'allAudioFileBytes': allAudioFileBytes,
        'allTranscriptBytes': allTranscriptBytes,
      };

  factory MeetingAsrHistoryStats.fromJson(Map<String, dynamic> json) {
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return MeetingAsrHistoryStats(
      userId: json['userId'] ?? 'anonymous',
      allAsrCalls: _asInt(json['allAsrCalls']),
      allAudioSeconds: _asInt(json['allAudioSeconds']),
      allAudioFileBytes: _asInt(json['allAudioFileBytes']),
      allTranscriptBytes: _asInt(json['allTranscriptBytes']),
    );
  }
}

// ============== 对象存储历史统计 ==============
// 👇 职责单一：仅统计对象存储累计数据
class MeetingStorageHistoryStats {
  String userId; // 用户ID
  int allStorageUploads; // 所有对象存储上传次数
  int allStorageBytes; // 所有存储文件总大小(字节)
  int allTransferBytes; // 所有传输总字节数

  MeetingStorageHistoryStats({
    required this.userId,
    required this.allStorageUploads,
    required this.allStorageBytes,
    required this.allTransferBytes,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'allStorageUploads': allStorageUploads,
        'allStorageBytes': allStorageBytes,
        'allTransferBytes': allTransferBytes,
      };

  factory MeetingStorageHistoryStats.fromJson(Map<String, dynamic> json) {
    int _asInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return MeetingStorageHistoryStats(
      userId: json['userId'] ?? 'anonymous',
      allStorageUploads: _asInt(json['allStorageUploads']),
      allStorageBytes: _asInt(json['allStorageBytes']),
      allTransferBytes: _asInt(json['allTransferBytes']),
    );
  }
}

// 👇 当需要同时展示两种统计时使用
class MeetingUsageDailySnapshot {
  String date;
  String userId;
  MeetingAsrDailyStats? asrStats;
  MeetingStorageDailyStats? storageStats;

  MeetingUsageDailySnapshot({
    required this.date,
    required this.userId,
    this.asrStats,
    this.storageStats,
  });
}

class MeetingUsageHistorySnapshot {
  String userId;
  MeetingAsrHistoryStats? asrStats;
  MeetingStorageHistoryStats? storageStats;

  MeetingUsageHistorySnapshot({
    required this.userId,
    this.asrStats,
    this.storageStats,
  });
}
