import 'package:hive/hive.dart';

part 'clip_suggestion.g.dart';

@HiveType(typeId: 0)
class ClipSuggestion extends HiveObject {
  @HiveField(0)
  final double startTimeSeconds;
  
  @HiveField(1)
  final double endTimeSeconds;
  
  @HiveField(2)
  final String title;
  
  @HiveField(3)
  final String reason;
  
  @HiveField(4)
  final int viralityScore;

  ClipSuggestion({
    required this.startTimeSeconds,
    required this.endTimeSeconds,
    required this.title,
    required this.reason,
    required this.viralityScore,
  });

  Map<String, dynamic> toJson() => {
    'start_time_seconds': startTimeSeconds,
    'end_time_seconds': endTimeSeconds,
    'title': title,
    'reason': reason,
    'virality_score': viralityScore,
  };

  factory ClipSuggestion.fromJson(Map<String, dynamic> json) => ClipSuggestion(
    startTimeSeconds: (json['start_time_seconds'] as num).toDouble(),
    endTimeSeconds: (json['end_time_seconds'] as num).toDouble(),
    title: json['title'] as String,
    reason: json['reason'] as String,
    viralityScore: json['virality_score'] as int,
  );
}
