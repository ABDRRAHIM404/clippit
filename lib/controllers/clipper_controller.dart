import 'dart:io';
import 'dart:isolate';
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
  String? _youtubeUrl;     // Persists the parsed YouTube URL if using the link path

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
  }) {
    // 🌟 Item 7: Guaranteed fallback cleanup on startup to purge any leftover aborted/crashed session files
    storageService.cleanLeftoverTempFilesOnStartup();
  }

  void _updateState(PipelineStatus status, {double? progress, String? message}) {
    _status = status;
    if (progress != null) _progress = progress;
    if (message != null) _statusMessage = message;
    notifyListeners();
  }

  /// Entry Point: Triggered when user enters a YouTube URL
  /// 🌟 Item 3 Optimization: Do NOT download the video first. Pass URL directly to Gemini.
  Future<void> processYouTubeInput(String url) async {
    _updateState(PipelineStatus.analyzingPass1, progress: 0.1, message: 'Pasting URL to Gemini...');
    _errorMessage = null;
    _youtubeUrl = url;

    try {
      final videoId = youtubeService.extractVideoId(url);
      _activeSourceIdOrHash = videoId;
      _activeSourceTitle = 'YouTube Video ($videoId)';

      // 1. Check database cache first to bypass analysis if already analyzed!
      final cached = dbService.getCachedSuggestions(videoId);
      if (cached != null) {
        _suggestions = cached;
        _updateState(PipelineStatus.showingHighlights, progress: 1.0, message: 'Loaded suggestions from cache');
        return;
      }

      // 2. 🌟 Item 3 Optimization: Call Gemini by passing the YouTube URL directly! No downloads.
      final suggestionsResult = await geminiService.analyzeVideoUrl(
        url,
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

  /// Entry Point: Triggered when user picks a local file
  /// 🌟 Item 4 Optimization: Compress local files over 200MB to 360p before uploading to Gemini.
  Future<void> processLocalFileInput(File file, String displayName) async {
    _updateState(PipelineStatus.hashing, progress: 0.1, message: 'Calculating unique file hash...');
    _errorMessage = null;
    _processedSourceFile = file;
    _activeSourceTitle = displayName;
    _youtubeUrl = null;

    try {
      // 🌟 Item 2: Move heavy file hashing into a separate Dart Isolate
      final String fileHash = await Isolate.run(() async {
        return await storageService.calculateFileHash(file);
      });
      _activeSourceIdOrHash = fileHash;

      // 2. Check cache
      final cached = dbService.getCachedSuggestions(fileHash);
      if (cached != null) {
        _suggestions = cached;
        _updateState(PipelineStatus.showingHighlights, progress: 1.0);
        return;
      }

      // 3. 🌟 Item 4 Check: If local file size > 200MB, compress it to 360p for Pass 1
      final int fileSize = await file.length();
      final int limit200Mb = 200 * 1024 * 1024; // 200 Megabytes in bytes

      if (fileSize > limit200Mb) {
        _updateState(PipelineStatus.hashing, progress: 0.3, message: 'Optimizing for upload (compressing to 360p)...');
        
        final tempDir = await storageService.getAppTempDirectory();
        final String compressedPath = '${tempDir.path}/compress_${DateTime.now().millisecondsSinceEpoch}.mp4';
        
        // Fast hardware or software scale to 360p
        final File compressedFile = await ffmpegService.compressVideoTo360p(
          inputFile: file,
          outputPath: compressedPath,
        );

        // Run Pass 1 Analysis using compressed file (much faster uploads!)
        await _runPass1Analysis(compressedFile);

        // Delete the compressed temp file immediately after Gemini finishes Pass 1
        try {
          if (await compressedFile.exists()) await compressedFile.delete();
        } catch (_) {}
      } else {
        // Run Pass 1 directly on the original video file as is (< 200MB)
        await _runPass1Analysis(file);
      }
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
      // 🌟 Item 3: If we are on the YouTube path, download the muxed stream ONLY now before cutting!
      if (_processedSourceFile == null && _youtubeUrl != null) {
        _updateState(PipelineStatus.downloading, progress: 0.1, message: 'Downloading segment streams from YouTube...');
        
        final File downloadedFile = await youtubeService.downloadAndMuxYouTubeVideo(
          url: _youtubeUrl!,
          outputDirectory: tempDir.path,
          ffmpegService: ffmpegService,
          onProgress: (p) {
            _updateState(PipelineStatus.downloading, progress: p, message: 'Downloading pre-muxed stream...');
          },
        );
        _processedSourceFile = downloadedFile;
      }

      if (_processedSourceFile == null) {
        throw Exception('Source video file could not be retrieved.');
      }

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

        // 2. Build the precise, completely relative aspect ratio math strings
        if (cropStyle == '9:16') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=2*trunc(ih*9/32):ih:(iw-2*trunc(ih*9/32))/2:0';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=2*trunc(ih*9/32):ih,boxblur=$blurRadius[bg];[v2]scale=2*trunc(ih*9/32):-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=2*trunc(ih*9/32):-2,pad=2*trunc(ih*9/32):ih:(ow-iw)/2:(oh-ih)/2:black';
          }
        } else if (cropStyle == '1:1') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=ih:ih:(iw-ih)/2:0';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=ih:ih,boxblur=$blurRadius[bg];[v2]scale=ih:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=ih:-2,pad=ih:ih:(ow-iw)/2:(oh-ih)/2:black';
          }
        } else if (cropStyle == '4:5') {
          if (backgroundFill == 'Crop') {
            cropFilterString = 'crop=2*trunc(ih*4/10):ih:(iw-2*trunc(ih*4/10))/2:0';
          } else if (backgroundFill == 'Blur Fill') {
            cropFilterString = 'split[v1][v2];[v1]scale=2*trunc(ih*4/10):ih,boxblur=$blurRadius[bg];[v2]scale=2*trunc(ih*4/10):-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2';
          } else { // Black Bars
            cropFilterString = 'scale=2*trunc(ih*4/10):-2,pad=2*trunc(ih*4/10):ih:(ow-iw)/2:(oh-ih)/2:black';
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
          cropStyle: cropStyle,
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

      // STEP 5: Generate Clip Thumbnail for History Dashboard (Compressed at 65%!)
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

      // 🌟 Item 7: Guaranteed automatic clean up of downloaded source, trimmed segments, and intermediate temp files
      await storageService.clearAllTemporaryFiles();
      // If we downloaded a YouTube video stream, delete it now so it consumes ZERO permanent device storage
      if (_youtubeUrl != null && _processedSourceFile != null) {
        try {
          if (await _processedSourceFile!.exists()) await _processedSourceFile!.delete();
        } catch (_) {}
        _processedSourceFile = null;
      }

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

  /// Wipes active controller state and triggers Item 7 temp sweeps
  void reset() {
    _status = PipelineStatus.idle;
    _progress = 0.0;
    _suggestions = [];
    _processedSourceFile = null;
    _renderedClipFile = null;
    _activeSourceTitle = '';
    _activeSourceIdOrHash = '';
    _youtubeUrl = null;
    _errorMessage = null;
    storageService.clearAllTemporaryFiles(); // 🌟 Item 7 Sweep
    notifyListeners();
  }
}
