class SpeechSegment {
  const SpeechSegment({
    required this.id,
    required this.speaker,
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  final String id;
  final String speaker;
  final String text;
  final int startMs;
  final int endMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'speaker': speaker,
        'text': text,
        'start_ms': startMs,
        'end_ms': endMs,
      };

  factory SpeechSegment.fromJson(Map<String, dynamic> json) => SpeechSegment(
        id: json['id'] as String,
        speaker: json['speaker'] as String? ?? '',
        text: json['text'] as String? ?? '',
        startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
        endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
      );

  SpeechSegment copyWith({String? speaker, String? text}) => SpeechSegment(
        id: id,
        speaker: speaker ?? this.speaker,
        text: text ?? this.text,
        startMs: startMs,
        endMs: endMs,
      );
}
