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
  File? _renderedClipFile; // Persists the finished render clip
  String _activeSourceTitle = '';
  String _activeSourceIdOrHash = '';

  // Getters
  PipelineStatus get status => _status;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  List<ClipSuggestion> get suggestions => _suggestions;
  File? get processedSourceFile => _processedSourceFile;
  File? get renderedClipFile => _renderedClipFile;
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
    required String cropStyle,       // 'Keep 16:9', '9:16', '1:1', '4:5'
    required String backgroundFill,   // 'Blur Fill', 'Crop', 'Black Bars'
    required String blurIntensity,   // 'Light', 'Medium', 'Heavy'
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

      // STEP 2: Configure Dynamic Aspect Ratio Crop Filter Chains
      if (cropStyle != 'Keep 16:9') {
        _updateState(PipelineStatus.trackingFaces, progress: 0.3, message: 'Configuring aspect ratio layers...');
        
        // 1. Resolve BoxBlur value based on selected intensity
        String blurRadius = '25:5'; // Medium
        if (blurIntensity == 'Light') blurRadius = '10:2';
        if (blurIntensity == 'Heavy') blurRadius = '50:10';

        // 2. Build the precise aspect ratio math strings
        if (cropStyle == '9:16') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=2*trunc(ih*9/32):ih:(iw-2*trunc(ih*9/32))/2:0,scale=1080:1920';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=$blurRadius[bg];[v2]scale=1080:608:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=1080:608,pad=1080:1920:(1080-iw)/2:(1920-ih)/2:black';
          }
        } else if (cropStyle == '1:1') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=ih:ih:(iw-ih)/2:0,scale=1080:1080';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=1080:1080:force_original_aspect_ratio=increase,crop=1080:1080,boxblur=$blurRadius[bg];[v2]scale=1080:608:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=1080:608,pad=1080:1080:(1080-iw)/2:(1080-ih)/2:black';
          }
        } else if (cropStyle == '4:5') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=2*trunc(ih*4/10):ih:(iw-2*trunc(ih*4/10))/2:0,scale=1080:1350';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=1080:1350:force_original_aspect_ratio=increase,crop=1080:1350,boxblur=$blurRadius[bg];[v2]scale=1080:608:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=1080:608,pad=1080:1350:(1080-iw)/2:(1350-ih)/2:black';
          }
        }
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
        isVertical: cropStyle != 'Keep 16:9',
        cropFilter: cropFilterString,
        assSubtitleFile: assFile,
      );

      _renderedClipFile = renderedClip;

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
    _renderedClipFile = null;
    _activeSourceTitle = '';
    _activeSourceIdOrHash = '';
    _errorMessage = null;
    notifyListeners();
  }
}
