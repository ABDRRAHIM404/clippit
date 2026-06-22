import 'package:hive/hive.dart';

part 'clip_history_entry.g.dart';

@HiveType(typeId: 1)
class ClipHistoryEntry extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String sourcePathOrUrl;

  @HiveField(2)
  final double startTime;

  @HiveField(3)
  final double endTime;

  @HiveField(4)
  final String title;

  @HiveField(5)
  final String localVideoPath;

  @HiveField(6)
  final String thumbnailPath;

  @HiveField(7)
  final DateTime createdAt;

  ClipHistoryEntry({
    required this.id,
    required this.sourcePathOrUrl,
    required this.startTime,
    required this.endTime,
    required this.title,
    required this.localVideoPath,
    required this.thumbnailPath,
    required this.createdAt,
  });
}
