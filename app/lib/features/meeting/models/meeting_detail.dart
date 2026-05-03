import 'speech_segment.dart';

/// Heavy meeting data — transcript / summary / mind-map / overview.
class MeetingDetail {
  const MeetingDetail({
    required this.meetingId,
    this.address = '',
    this.personnel = '',
    this.overview = '',
    this.summary = '',
    this.mindmapHtml = '',
    this.segments = const [],
  });

  final String meetingId;
  final String address;
  final String personnel;

  /// Overview — newline-separated bullet list.
  final String overview;

  /// Summary — markdown.
  final String summary;

  /// Mind-map HTML, embedded in WebView.
  final String mindmapHtml;

  /// Speech transcript segments.
  final List<SpeechSegment> segments;

  MeetingDetail copyWith({
    String? address,
    String? personnel,
    String? overview,
    String? summary,
    String? mindmapHtml,
    List<SpeechSegment>? segments,
  }) =>
      MeetingDetail(
        meetingId: meetingId,
        address: address ?? this.address,
        personnel: personnel ?? this.personnel,
        overview: overview ?? this.overview,
        summary: summary ?? this.summary,
        mindmapHtml: mindmapHtml ?? this.mindmapHtml,
        segments: segments ?? this.segments,
      );

  Map<String, dynamic> toJson() => {
        'meeting_id': meetingId,
        'address': address,
        'personnel': personnel,
        'overview': overview,
        'summary': summary,
        'mindmap_html': mindmapHtml,
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory MeetingDetail.fromJson(Map<String, dynamic> json) => MeetingDetail(
        meetingId: json['meeting_id'] as String,
        address: json['address'] as String? ?? '',
        personnel: json['personnel'] as String? ?? '',
        overview: json['overview'] as String? ?? '',
        summary: json['summary'] as String? ?? '',
        mindmapHtml: json['mindmap_html'] as String? ?? '',
        segments: (json['segments'] as List?)
                ?.map((e) => SpeechSegment.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
      );
}
