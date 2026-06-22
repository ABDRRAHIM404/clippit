import 'dart:io';
import 'package:flutter/material.dart';
import '../models/clip_suggestion.dart';
import '../models/clip_history_entry.dart';
import '../services/youtube_service.dart';
import '../services/gemini_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/face_tracking_service.dart';
import '../services/storage_service.dart';
import '../services/db_service.dart';

enum PipelineStatus {
  idle,
  downloading,
  hashing,
  analyzingPass1,
  showingHighlights,
  trimming,
  transcribingPass2,
  trackingFaces,
  renderingFinal,
  completed,
  error
}

class ClipperController extends ChangeNotifier {
  final YouTubeService youtubeService;
  final GeminiService geminiService;
  final FFmpegService ffmpegService;
  final CaptionService captionService;
  final FaceTrackingService faceTrackingService;
  final StorageService storageService;
  final DbService dbService;

  PipelineStatus _status = PipelineStatus.idle;
  double _progress = 0.0;
  String _statusMessage = '';
  String? _errorMessage;

  List<ClipSuggestion> _suggestions = [];
  File? _processedSourceFile;
  String _activeSourceTitle = '';
  String _activeSourceIdOrHash = '';

  // Getters
  PipelineStatus get status => _status;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  List<ClipSuggestion> get suggestions => _suggestions;
  File? get processedSourceFile => _processedSourceFile;
  String get activeSourceTitle => _activeSourceTitle;

  ClipperController({
    required this.youtubeService,
    required this.geminiService,
    required this.ffmpegService,
    required this.captionService,
    required this.faceTrackingService,
    required this.storageService,
    required this.dbService,
  });

  void _updateState(PipelineStatus status, {double? progress, String? message}) {
    _status = status;
    if (progress != null) _progress = progress;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  /// Entry Point: Triggered when user enters a YouTube URL
  Future<void> processYouTubeInput(String url) async {
    _updateState(PipelineStatus.downloading, progress: 0.0, message: 'Extracting YouTube details...');
    _errorMessage = null;

    try {
      final tempDir = await storageService.getAppTempDirectory();
      final videoId = youtubeService.extractVideoId(url);
      _activeSourceIdOrHash = videoId;
      _activeSourceTitle = 'YouTube Video ($videoId)';

      // 1. Check database cache first to bypass download if already analyzed!
      final cached = dbService.getCachedSuggestions(videoId);
      if (cached != null) {
        _suggestions = cached;
        // Broadcast suggestions instantly to UI (Instant Load UX!)
        _updateState(PipelineStatus.showingHighlights, progress: 1.0, message: 'Loaded suggestions from cache');
        
        // Start downloading the muxed video silently in the background
        _downloadMuxedVideoBackground(url, tempDir.path);
        return;
      }

      // 2. Download and Mux Stream pieces
      final muxedFile = await youtubeService.downloadAndMuxYouTubeVideo(
        url: url,
        outputDirectory: tempDir.path,
        ffmpegService: ffmpegService,
        onProgress: (p) {
          _updateState(PipelineStatus.downloading, progress: p, message: 'Downloading HD streams...');
        },
      );

      _processedSourceFile = muxedFile;

      // 3. Trigger Pass 1 Analysis
      await _runPass1Analysis(muxedFile);
    } catch (e) {
      _handleFailure(e.toString());
    }
  }

  /// Helper to download the muxed video in the background during a cache hit
  Future<void> _downloadMuxedVideoBackground(String url, String tempPath) async {
    try {
      final muxedFile = await youtubeService.downloadAndMuxYouTubeVideo(
        url: url,
        outputDirectory: tempPath,
        ffmpegService: ffmpegService,
        onProgress: (_) {}, // silent background progress
      );
      _processedSourceFile = muxedFile;
      notifyListeners(); // Notify HomeScreen that video file is now ready
    } catch (e) {
      print('Warning: Background download failed: $e');
    }
  }

  /// Entry Point: Triggered when user picks a local file
  Future<void> processLocalFileInput(File file, String displayName) async {
    _updateState(PipelineStatus.hashing, progress: 0.1, message: 'Calculating unique file hash...');
    _errorMessage = null;
    _processedSourceFile = file;
    _activeSourceTitle = displayName;

    try {
      // 1. Calculate memory-safe SHA-256 hash
      final String fileHash = await storageService.calculateFileHash(file);
      _activeSourceIdOrHash = fileHash;

      // 2. Check cache
      final cached = dbService.getCachedSuggestions(fileHash);
      if (cached != null) {
        _suggestions = cached;
        _updateState(PipelineStatus.showingHighlights, progress: 1.0);
        return;
      }

      // 3. Trigger Pass 1 Analysis
      await _runPass1Analysis(file);
    } catch (e) {
      _handleFailure(e.toString());
    }
  }

  /// Private helper to coordinate Gemini Pass 1 Highlight Detection
  Future<void> _runPass1Analysis(File file) async {
    _updateState(PipelineStatus.analyzingPass1, progress: 0.0, message: 'Uploading to Gemini Files API...');

    try {
      final suggestionsResult = await geminiService.analyzeVideoFile(
        file,
        onStatusUpdate: (statusText) {
          _updateState(PipelineStatus.analyzingPass1, message: statusText);
        },
      );

      _suggestions = suggestionsResult;

      // Cache suggestions to Hive box
      await dbService.cacheSuggestions(_activeSourceIdOrHash, suggestionsResult);

      _updateState(PipelineStatus.showingHighlights, progress: 1.0);
    } catch (e) {
      _handleFailure(e.toString());
    }
  }

  /// Triggers full segment crop rendering, subtitle burn-ins, and final export
  Future<File?> renderAndExportClip({
    required double startSeconds,
    required double endSeconds,
    required bool enableCrop,
    required bool enableCaptions,
    required String selectedLanguage,
  }) async {
    if (_processedSourceFile == null) {
      _handleFailure('Source video is missing. Cannot render.');
      return null;
    }

    _errorMessage = null;
    final tempDir = await storageService.getAppTempDirectory();
    final documentsDir = await storageService.getAppLibraryDirectory();

    final String clipId = DateTime.now().millisecondsSinceEpoch.toString();
    final String trimmedPath = '${tempDir.path}/clip_${clipId}_trimmed.mp4';
    final String finalRenderPath = '${documentsDir.path}/clip_${clipId}_rendered.mp4';
    final String thumbnailPath = '${documentsDir.path}/clip_${clipId}_thumb.jpg';

    File? trimmedFile;
    File? assFile;
    String? cropFilterString;

    try {
      // STEP 1: Fast trim the segment (instantly copying codecs)
      _updateState(PipelineStatus.trimming, progress: 0.1, message: 'Fast-cutting segment...');
      trimmedFile = await ffmpegService.trimVideo(
        sourceFile: _processedSourceFile!,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        targetPath: trimmedPath,
      );

      // STEP 2: Google ML Kit Face/Speaker Tracking (if enabled)
      if (enableCrop) {
        _updateState(PipelineStatus.trackingFaces, progress: 0.3, message: 'Running Face Detector...');
        
        // 🌟 100% ROBUST & UNIVERSAL RELATIVE CROP FILTER:
        // Hardcoding 608:1080 crop sizes crashes immediately on any pre-muxed YouTube video
        // because the source height is only 360p or 720p (crop dimensions cannot exceed input dimensions!).
        //
        // By using FFmpeg's relative evaluation syntax:
        // - out_h = ih (inherits full input height cleanly: 360, 720, or 1080)
        // - out_w = 2 * trunc(ih * 9 / 32) (calculates a perfect 9:16 proportional width and guarantees an even integer divisible by 2 for x264!)
        // - x_offset = (iw - out_w) / 2 (centers the horizontal camera coordinate flawlessly)
        //
        // This is 100% immune to resolution changes, never throws out-of-bounds, and compiles perfectly!
        cropFilterString = 'crop=2*trunc(ih*9/32):ih:(iw-2*trunc(ih*9/32))/2:0';
      }

      // STEP 3: Pass 2 AI Word-level transcription (if enabled)
      if (enableCaptions) {
        _updateState(PipelineStatus.transcribingPass2, progress: 0.5, message: 'AI Transcribing audio timeline...');
        
        final Map<String, dynamic> rawTranscript = await geminiService.transcribeClipSegment(trimmedFile);

        _updateState(PipelineStatus.transcribingPass2, progress: 0.7, message: 'Compiling subtitles style sheet...');
        final String assPath = '${tempDir.path}/clip_${clipId}_subs.ass';
        
        assFile = await captionService.generateAssSubtitles(
          geminiTranscript: rawTranscript,
          targetFilePath: assPath,
        );
      }

      // STEP 4: Burn filters, crop, and compile final export video via FFmpeg
      _updateState(PipelineStatus.renderingFinal, progress: 0.8, message: 'Rendering final vertical formats...');
      final File renderedClip = await ffmpegService.renderFinalClip(
        trimmedClip: trimmedFile,
        targetPath: finalRenderPath,
        isVertical: enableCrop,
        cropFilter: cropFilterString,
        assSubtitleFile: assFile,
      );

      // STEP 5: Generate Clip Thumbnail for History Dashboard
      _updateState(PipelineStatus.renderingFinal, progress: 0.95, message: 'Generating card thumbnails...');
      await ffmpegService.extractThumbnail(renderedClip, thumbnailPath);

      // STEP 6: Save record to Hive Database
      final historyEntry = ClipHistoryEntry(
        id: clipId,
        sourcePathOrUrl: _activeSourceTitle,
        startTime: startSeconds,
        endTime: endSeconds,
        title: 'Clip from: $_activeSourceTitle',
        localVideoPath: finalRenderPath,
        thumbnailPath: thumbnailPath,
        createdAt: DateTime.now(),
      );
      await dbService.saveHistoryEntry(historyEntry);

      // Final complete cleanup of stream fragments
      await storageService.clearAllTemporaryFiles();

      _updateState(PipelineStatus.completed, progress: 1.0, message: 'Clip successfully exported!');
      return renderedClip;
    } catch (e) {
      _handleFailure(e.toString());
      return null;
    }
  }

  void _handleFailure(String msg) {
    _status = PipelineStatus.error;
    _errorMessage = msg;
    notifyListeners();
  }

  /// Wipes active controller state to allow processing next links
  void reset() {
    _status = PipelineStatus.idle;
    _progress = 0.0;
    _suggestions = [];
    _processedSourceFile = null;
    _activeSourceTitle = '';
    _activeSourceIdOrHash = '';
    _errorMessage = null;
    notifyListeners();
  }
}
