import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/clip_suggestion.dart';
import '../models/clip_history_entry.dart';

class DbService {
  static const String cacheBoxName = 'analysis_cache_box';
  static const String historyBoxName = 'clip_history_box';

  late Box<List<dynamic>> _cacheBox;
  late Box<ClipHistoryEntry> _historyBox;

  /// Setup and initialize Hive databases & register adapters
  Future<void> initialize() async {
    await Hive.initFlutter();

    // Register Hive type adapters for our data schemas
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ClipSuggestionAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(ClipHistoryEntryAdapter());
    }

    // Open boxes
    _cacheBox = await Hive.openBox<List<dynamic>>(cacheBoxName);
    _historyBox = await Hive.openBox<ClipHistoryEntry>(historyBoxName);
  }

  // --- PASS 1: HIGHLIGHT ANALYSIS CACHE METHODS ---

  /// Retrieve cached suggestions for a video URL or unique file hash
  List<ClipSuggestion>? getCachedSuggestions(String videoIdOrHash) {
    final cachedData = _cacheBox.get(videoIdOrHash);
    if (cachedData == null) return null;
    
    return cachedData.map((e) => e as ClipSuggestion).toList();
  }

  /// Cache suggestions to prevent subsequent API bills
  Future<void> cacheSuggestions(String videoIdOrHash, List<ClipSuggestion> suggestions) async {
    await _cacheBox.put(videoIdOrHash, suggestions);
  }

  // --- PASS 2: HISTORICAL SAVED CLIPS METHODS ---

  /// Retrieve all historical entries sorted by date descending (newest first)
  List<ClipHistoryEntry> getAllHistory() {
    final list = _historyBox.values.toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Saves a newly compiled video clip to local history logs
  Future<void> saveHistoryEntry(ClipHistoryEntry entry) async {
    await _historyBox.put(entry.id, entry);
  }

  /// Deletes a historical record and cleans up associated localized media files
  Future<void> deleteHistoryEntry(String entryId) async {
    final entry = _historyBox.get(entryId);
    if (entry != null) {
      // 1. Delete associated local video file
      try {
        final videoFile = File(entry.localVideoPath);
        if (await videoFile.exists()) {
          await videoFile.delete();
        }
      } catch (e) {
        print('Error clearing history video file: $e');
      }

      // 2. Delete associated clip thumbnail
      try {
        final thumbFile = File(entry.thumbnailPath);
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      } catch (e) {
        print('Error clearing history thumbnail file: $e');
      }

      // 3. Clear database record
      await _historyBox.delete(entryId);
    }
  }

  /// Utility clean up helper to wipe databases (e.g. settings page "Reset Cache")
  Future<void> clearAllCache() async {
    await _cacheBox.clear();
  }
}
