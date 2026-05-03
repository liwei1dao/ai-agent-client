import 'dart:convert';

/// Meeting recording type — same semantics as the source project
/// (`audioType` field on the legacy controller).
enum MeetingAudioType { live, audioVideo, call }

extension MeetingAudioTypeX on MeetingAudioType {
  int get index => switch (this) {
        MeetingAudioType.live => 0,
        MeetingAudioType.audioVideo => 1,
        MeetingAudioType.call => 2,
      };

  static MeetingAudioType fromIndex(int? i) => switch (i) {
        1 => MeetingAudioType.audioVideo,
        2 => MeetingAudioType.call,
        _ => MeetingAudioType.live,
      };
}

/// Lightweight summary used by the list screen. Heavy fields (transcript,
/// summary, mind-map JSON) live in [MeetingDetail].
class Meeting {
  const Meeting({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.durationMs,
    required this.audioType,
    required this.audioPath,
    this.marked = false,
    this.tags = const [],
    this.uploaded = false,
    this.transcribed = false,
    this.serverId = 0,
    this.audioUrl = '',
  });

  /// 本地 UUID — 即使未联网也能生成。
  final String id;
  final String title;
  final DateTime createdAt;
  final int durationMs;
  final MeetingAudioType audioType;
  final String audioPath;
  final bool marked;
  final List<String> tags;
  final bool uploaded;
  final bool transcribed;

  /// 服务端为该会议分配的整型 id（`echomeet_addrecord` 后回填）。
  /// 0 表示尚未在服务端建过。
  final int serverId;

  /// 上传到腾讯 COS 后的 URL。空字符串表示尚未上传。
  final String audioUrl;

  Meeting copyWith({
    String? title,
    int? durationMs,
    bool? marked,
    List<String>? tags,
    bool? uploaded,
    bool? transcribed,
    String? audioPath,
    int? serverId,
    String? audioUrl,
  }) =>
      Meeting(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        durationMs: durationMs ?? this.durationMs,
        audioType: audioType,
        audioPath: audioPath ?? this.audioPath,
        marked: marked ?? this.marked,
        tags: tags ?? this.tags,
        uploaded: uploaded ?? this.uploaded,
        transcribed: transcribed ?? this.transcribed,
        serverId: serverId ?? this.serverId,
        audioUrl: audioUrl ?? this.audioUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'created_at': createdAt.millisecondsSinceEpoch,
        'duration_ms': durationMs,
        'audio_type': audioType.index,
        'audio_path': audioPath,
        'marked': marked,
        'tags': tags,
        'uploaded': uploaded,
        'transcribed': transcribed,
        'server_id': serverId,
        'audio_url': audioUrl,
      };

  factory Meeting.fromJson(Map<String, dynamic> json) => Meeting(
        id: json['id'] as String,
        title: json['title'] as String? ?? '未命名会议',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (json['created_at'] as num).toInt()),
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
        audioType: MeetingAudioTypeX.fromIndex(
            (json['audio_type'] as num?)?.toInt()),
        audioPath: json['audio_path'] as String? ?? '',
        marked: json['marked'] as bool? ?? false,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        uploaded: json['uploaded'] as bool? ?? false,
        transcribed: json['transcribed'] as bool? ?? false,
        serverId: (json['server_id'] as num?)?.toInt() ?? 0,
        audioUrl: json['audio_url'] as String? ?? '',
      );

  String encode() => jsonEncode(toJson());
}
