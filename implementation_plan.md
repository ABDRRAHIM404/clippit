# Clippit: AI-Powered YouTube Highlight Clipper
## Detailed Engineering & Implementation Plan (Revised - June 2026)

This implementation plan outlines the architectural decisions, data models, custom services, AI prompts, face-tracking algorithms, and CI/CD pipelines to build **Clippit**, a personal-use Android application built with Flutter.

*This revised plan resolves critical blockers regarding deprecated packages (`ffmpeg_kit_flutter` has been replaced with the modern, active `ffmpeg_kit_flutter_new` fork) and hardcoded Gemini models (rearchitected to support modern/configurable model targets like Gemini 1.5 Pro, 2.0 Flash, or 2.5 Flash).*

---

## Table of Contents
1. **Architectural Overview & State Machine**
2. **Database & Caching Strategy**
3. **Core Dependencies (`pubspec.yaml`)**
4. **AI Prompts & Structured JSON Schemas (Gemini API)**
5. **Key Service Skeletons & Implementations**
    - `GeminiService` (Dynamic Models & Two-Pass Analysis)
    - `FFmpegService` (Trimming, Cropping, Burn-in via Modern Fork)
    - `FaceTrackingService` (ML Kit Smart Crop)
    - `CaptionService` (ASS Caption Styling)
    - `YouTubeService` (Pure Dart vs Native)
6. **Detailed Dynamic / Smart Cropping Algorithm**
7. **GitHub Actions CI/CD Configuration**
8. **Phased Implementation Timeline & Milestones**
9. **Critical Pitfalls, Edge Cases, & Mitigations**

---

## 1. Architectural Overview & State Machine

Clippit operates as a single-device, wizard-like sequential pipeline. To keep state management clean, lightweight, and predictable, we use a central State Machine governed by a `ClipperController` (implemented via `ChangeNotifier` or `StateNotifier` with Riverpod).

### State Transition Diagram

```
[ Idle State ]
      │ (User enters YouTube URL or selects local file)
      ▼
[ Processing State: Input Processing ]
      │ (Download YouTube streams / calculate hash of local file)
      ▼
[ Processing State: Cache Check ]
      ├───► (Cache Hit: Load suggestions from Hive) ───┐
      │                                                │
      ▼ (Cache Miss)                                   │
[ Processing State: Gemini Pass 1 Analysis ]           │
      │ (Upload to Files API / Analyze video)          │
      ├────────────────────────────────────────────────┘
      ▼
[ Highlights View State ]
      │ (User selects/reviews clip suggestion)
      ▼
[ Edit & Preview State ]
      │ (User fine-tunes timestamps / toggles vertical crop & captions)
      ▼
[ Processing State: Cutting Clip ]
      │ (FFmpeg fast-cut segment)
      ▼
[ Processing State: Gemini Pass 2 Transcribing ]
      │ (Upload clip to Files API / transcribe clip-relative audio)
      ▼
[ Processing State: Burning & Rendering ]
      │ (Generate ASS subtitles, run face tracker, crop, and burn-in overlay)
      ▼
[ Export & Share State ]
      │ (User saves to Gallery or shares to TikTok/Reels/Shorts)
```

### Clipper State Enum
```dart
enum ClipperStatus {
  idle,
  processingInput,       // Downloading or hashing video
  checkingCache,         // Verifying Hive database for cached highlights
  analyzingPass1,        // Calling Gemini to get highlight suggestions
  displayingHighlights,   // Presenting card list to user
  editingClip,           // Reviewing, scrubbing, toggling settings
  cuttingClip,           // Fast-trimming video with FFmpeg (-c copy)
  transcribingPass2,     // Transcribing ONLY the cut clip with Gemini
  renderingClip,         // Dynamic tracking, cropping, burn-in captions
  exportSuccess,         // Completed and ready to share
  failure                // Error state with message
}
```

---

## 2. Database & Caching Strategy

Since Clippit runs strictly on-device, we use **Hive** for fast, lightweight NoSQL key-value storage. 

### Database Boxes
1. **`analysis_cache_box`**: Caches Pass 1 Gemini analyses.
   - **Key**: Video Unique Identifier (YouTube Video ID or SHA-256 hash of local video file).
   - **Value**: `List<ClipSuggestion>` (stored as a JSON string or Hive-adapted model).
   - **Benefit**: Re-opening a 1-hour video costs 0 additional Gemini API tokens.
2. **`clip_history_box`**: Stores records of generated clips.
   - **Key**: Unique UUID of the generated clip.
   - **Value**: `ClipHistoryEntry` object containing paths to the rendered video, generated thumbnail, source details, timestamps, and platform metadata.

### Models Spec

```dart
import 'package:hive/hive.dart';

part 'clip_models.g.dart';

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
```

---

## 3. Core Dependencies (`pubspec.yaml`)

To resolve the blocker of `ffmpeg_kit_flutter_full_gpl` being discontinued and unavailable for modern Gradle/Android builds, we migrate to **`ffmpeg_kit_flutter_new`**, which is the active, community-maintained drop-in replacement that compiles flawlessly with Android V2 bindings, Flutter 3+, and updated Kotlin SDKs.

This package includes support for the **`libass`** library in its default Full configurations, enabling advanced styled caption burn-ins.

```yaml
name: clippit
description: AI-Powered YouTube Highlight Clipper
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # UI and Navigation
  cupertino_icons: ^1.0.5
  flutter_riverpod: ^2.4.9    # Highly-scalable state management
  google_fonts: ^6.1.0        # Dark-theme modern typography
  video_player: ^2.8.1        # Inline editing preview
  chewie: ^1.7.1              # High-level video player UI controls

  # AI & Cloud API
  google_generative_ai: ^0.2.0 # Official Gemini API Dart wrapper

  # Local Media Downloading & Processing
  youtube_explode_dart: ^2.2.1 # Pure Dart YT download - extremely robust & CI-build-friendly
  ffmpeg_kit_flutter_new: ^3.1.0 # Modern, maintained FFmpeg Kit (Full-GPL version by default!)

  # On-Device ML
  google_mlkit_face_detection: ^0.11.0 # High-speed free local face-tracking

  # Local Database
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  shared_preferences: ^2.2.2

  # Device Utility Packages
  path_provider: ^2.1.1       # File directories
  share_plus: ^7.2.1          # Native share sheets
  crypto: ^3.0.3              # Hashing video files for caching
  uuid: ^4.3.3                # ID generation
  intl: ^0.19.0               # Formatting timestamps

dev_dependencies:
  flutter_test:
    sdk: flutter
  hive_generator: ^2.0.1
  build_runner: ^2.4.8
```

---

## 4. AI Prompts & Structured JSON Schemas

Using Gemini, we pass JSON Schema constraints directly in the API request settings. This guarantees that Gemini will output valid, parseable JSON arrays without conversational markdown wrappers (` ```json `), preventing parsing errors.

### Pass 1: Highlight Detection Prompt
*Goal:* Scan the full video and output moments (60–75 seconds) scored for virality and high viewer retention.

*System Instruction:*
> You are an elite content strategist and short-form video editor. Your task is to analyze the provided video and identify the absolute best highlights (between 60 and 75 seconds in length). Focus on sections with high narrative energy, dramatic reveals, complete conversational thoughts, humor, or intense visual action. The hook must occur in the first 5 seconds of the clip.
>
> You MUST return results adhering strictly to the JSON schema provided.

*Schema Constraint (OpenAPI schema format passed to Gemini SDK):*
```json
{
  "type": "OBJECT",
  "properties": {
    "highlights": {
      "type": "ARRAY",
      "items": {
        "type": "OBJECT",
        "properties": {
          "start_time_seconds": { "type": "NUMBER", "description": "The exact starting timestamp in seconds" },
          "end_time_seconds": { "type": "NUMBER", "description": "The exact ending timestamp in seconds (60-75s gap from start)" },
          "title": { "type": "STRING", "description": "Catchy, click-worthy title for the highlight" },
          "reason": { "type": "STRING", "description": "Compelling narrative explanation for why this is viral material" },
          "virality_score": { "type": "INTEGER", "description": "A score between 1 and 100 representing emotional/hook strength" }
        },
        "required": ["start_time_seconds", "end_time_seconds", "title", "reason", "virality_score"]
      }
    }
  },
  "required": ["highlights"]
}
```

### Pass 2: Word-Level Caption Transcription Prompt
*Goal:* Generate highly accurate captions starting from relative time `0.00` with emphasis identifiers.

*System Instruction:*
> You are an expert closed-caption transcriber. You are transcribing a trimmed video clip that starts at exactly 0.00. Listen to the audio and produce an array of word/sentence segments with accurate microsecond-level timestamps relative to the clip's start.
> Identify 1 to 3 "keywords" in each segment that are heavily stressed, loud, or critical to the emotional context of the sentence; these will be highlighted in yellow or cyan during render.
>
> You MUST output strictly according to the defined JSON schema. Do not output conversational text or markdown wrappers.

*Schema Constraint:*
```json
{
  "type": "OBJECT",
  "properties": {
    "segments": {
      "type": "ARRAY",
      "items": {
        "type": "OBJECT",
        "properties": {
          "start_time_ms": { "type": "INTEGER", "description": "Start of segment in milliseconds relative to clip start (0)" },
          "end_time_ms": { "type": "INTEGER", "description": "End of segment in milliseconds relative to clip start" },
          "text": { "type": "STRING", "description": "The transcribed spoken words in this segment" },
          "keywords": {
            "type": "ARRAY",
            "items": { "type": "STRING" },
            "description": "1 to 3 specific key words from the 'text' to stylize/emphasize"
          }
        },
        "required": ["start_time_ms", "end_time_ms", "text", "keywords"]
      }
    }
  },
  "required": ["segments"]
}
```

---

## 5. Key Service Skeletons & Implementations

### A. `GeminiService` (`lib/services/gemini_service.dart`)
This implementation makes models dynamically configurable in the constructor. We can dynamically use highly advanced models (like `gemini-1.5-pro` or the newer `gemini-2.5-flash` / `gemini-2.0-pro` families) by injecting them through settings, preventing future code obsolescence.

```dart
import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/clip_suggestion.dart';

class GeminiService {
  final String apiKey;
  final String analysisModelName;       // Dynamically injected (e.g. 'gemini-1.5-pro' or 'gemini-2.5-flash')
  final String transcriptionModelName;  // Dynamically injected (e.g. 'gemini-1.5-flash')
  
  late final GenerativeModel _model;
  late final GenerativeModel _transcribeModel;

  GeminiService({
    required this.apiKey,
    this.analysisModelName = 'gemini-1.5-pro',       // Default to deep visual understanding model
    this.transcriptionModelName = 'gemini-1.5-flash', // Default to fast audio transcriber
  }) {
    // Configure Model 1 (Analysis) with JSON schema constraints
    _model = GenerativeModel(
      model: analysisModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'highlights': Schema.array(
              items: Schema.object(
                properties: {
                  'start_time_seconds': Schema.number(),
                  'end_time_seconds': Schema.number(),
                  'title': Schema.string(),
                  'reason': Schema.string(),
                  'virality_score': Schema.integer(),
                },
                requiredProperties: ['start_time_seconds', 'end_time_seconds', 'title', 'reason', 'virality_score'],
              ),
            ),
          },
          requiredProperties: ['highlights'],
        ),
      ),
    );

    // Configure Model 2 (Transcription) with JSON schema constraints
    _transcribeModel = GenerativeModel(
      model: transcriptionModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: Schema.object(
          properties: {
            'segments': Schema.array(
              items: Schema.object(
                properties: {
                  'start_time_ms': Schema.integer(),
                  'end_time_ms': Schema.integer(),
                  'text': Schema.string(),
                  'keywords': Schema.array(items: Schema.string()),
                },
                requiredProperties: ['start_time_ms', 'end_time_ms', 'text', 'keywords'],
              ),
            ),
          },
          requiredProperties: ['segments'],
        ),
      ),
    );
  }

  /// Pass 1: Analysis (Video URL or Uploaded Local File path)
  Future<List<ClipSuggestion>> analyzeVideoFile(File videoFile) async {
    // 1. Upload using Gemini File API (Recommended for large files > 20MB)
    final FileRef fileRef = await _uploadToFilesApi(videoFile);

    // 2. Poll status until active
    await _pollFileStatus(fileRef);

    // 3. Prompt the model
    final response = await _model.generateContent([
      Content.multi([
        fileRef,
        TextPart('Analyze this video and return the top viral highlights. Keep recommended duration strictly between 60 and 75 seconds.')
      ])
    ]);

    // 4. Cleanup API storage
    await _deleteFileFromApi(fileRef.name);

    if (response.text == null) throw Exception('Empty response from Gemini');
    
    final Map<String, dynamic> parsed = jsonDecode(response.text!);
    final List<dynamic> highlightsJson = parsed['highlights'];
    return highlightsJson.map((x) => ClipSuggestion.fromJson(x)).toList();
  }

  /// Pass 2: Clip Subtitle Transcription
  Future<Map<String, dynamic>> transcribeClipSegment(File trimmedClip) async {
    final FileRef fileRef = await _uploadToFilesApi(trimmedClip);
    await _pollFileStatus(fileRef);

    final response = await _transcribeModel.generateContent([
      Content.multi([
        fileRef,
        TextPart('Transcribe this exact clip segment. Output start and end times in relative milliseconds from the absolute beginning (0:00). Identify 1-3 highly expressive keywords per segment to emphasize.')
      ])
    ]);

    await _deleteFileFromApi(fileRef.name);

    if (response.text == null) throw Exception('Failed to transcribe');
    return jsonDecode(response.text!);
  }

  // Implementation-specific helpers for Gemini File Upload API:
  Future<FileRef> _uploadToFilesApi(File file) async {
    // Uses multipart HTTP requests to "https://generativelanguage.googleapis.com/v1beta/files"
    // and returns a FileRef reference.
    throw UnimplementedError("File upload API integration");
  }

  Future<void> _pollFileStatus(FileRef fileRef) async {
    // Polls the file endpoint until state is 'ACTIVE'
  }

  Future<void> _deleteFileFromApi(String fileName) async {
    // Calls DELETE on the API to free space immediately
  }
}

// Custom wrapper to fit GenerativeModel upload specification
class FileRef extends Part {
  final String name;
  final String mimeType;
  FileRef(this.name, this.mimeType);

  @override
  Map<String, dynamic> toJson() => {
    'fileData': {
      'fileUri': name,
      'mimeType': mimeType,
    }
  };
}
```

---

### B. `FFmpegService` (`lib/services/ffmpeg_service.dart`)
Using the **`ffmpeg_kit_flutter_new`** API to coordinate fast-cuts, thumbnail extractions, cropping, and overlay burns.

```dart
import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class FFmpegService {
  /// Step 1: Fast cut using stream copying (extremely fast, zero re-encode)
  Future<File> trimVideo({
    required File sourceFile,
    required double startSeconds,
    required double endSeconds,
    required String targetPath,
  }) async {
    final duration = endSeconds - startSeconds;
    // Command: -ss before -i makes it super-fast, seeking immediately.
    // -c copy ensures stream copy (no rendering yet!)
    final cmd = '-ss $startSeconds -i "${sourceFile.path}" -t $duration -c copy -y "$targetPath"';
    
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return File(targetPath);
    } else {
      final logs = await session.getLogs();
      throw Exception('FFmpeg Trim Failed: ${logs.join("\n")}');
    }
  }

  /// Step 2: Full Render (Smart Crop + Subtitles + Watermark Overlay)
  Future<File> renderFinalClip({
    required File trimmedClip,
    required String targetPath,
    required bool isVertical,
    String? cropFilter,         // e.g., "crop=607:1080:x_val:0"
    File? assSubtitleFile,      // Generated styled ASS caption file
    File? watermarkPng,         // Overlay logo path
  }) async {
    List<String> filters = [];

    // 1. Aspect Ratio Crop
    if (isVertical && cropFilter != null) {
      filters.add(cropFilter);
    }

    // 2. ASS Subtitle Burn-In
    if (assSubtitleFile != null) {
      // libass utilizes the "ass" filter. Crucial: escaping paths for platform safety.
      final escapedAssPath = assSubtitleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
      filters.add("ass='$escapedAssPath'");
    }

    // 3. Watermark Overlay
    String inputArgs = '-i "${trimmedClip.path}"';
    if (watermarkPng != null) {
      inputArgs += ' -i "${watermarkPng.path}"';
      // Places watermark top-right, padded by 20px
      filters.add("[0:v][1:v]overlay=main_w-overlay_w-20:20[outv]");
    }

    String filterChain = "";
    if (filters.isNotEmpty) {
      if (watermarkPng != null) {
        filterChain = '-filter_complex "${filters.sublist(0, filters.length - 1).join(",")},[1:v]overlay=main_w-overlay_w-20:20"';
      } else {
        filterChain = '-vf "${filters.join(",")}"';
      }
    }

    // Re-encoding is required for crop/burn filters.
    // We use high-speed preset libx264, medium crf (23) for balance of quality and rendering speed on phone hardware.
    final cmd = '$inputArgs $filterChain -c:v libx264 -preset superfast -crf 23 -c:a aac -b:a 128k -y "$targetPath"';

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return File(targetPath);
    } else {
      final logs = await session.getLogs();
      throw Exception('FFmpeg Render Failed: ${logs.join("\n")}');
    }
  }

  /// Grab clip thumbnail for Hive History Dashboard
  Future<File> extractThumbnail(File videoFile, String targetJpgPath) async {
    final cmd = '-i "${videoFile.path}" -ss 00:00:02.000 -vframes 1 -q:v 2 -y "$targetJpgPath"';
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return File(targetJpgPath);
    } else {
      throw Exception('Thumbnail extraction failed');
    }
  }
}
```

---

### C. `FaceTrackingService` (`lib/services/face_tracking_service.dart`)
Utilizes local ML Kit on-device face detection to calculate dynamic frame movement coordinates.

```dart
import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceTrackingService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      mode: FaceDetectorMode.fast, // High performance prioritization
      enableClassification: false,
      enableTracking: true,        // Enable ID retention across frames
    ),
  );

  /// Analyzes sampled frames of the video clip to compute face position arrays
  Future<List<double>> computeSpeakerXCoordinates({
    required File videoFile,
    required double videoWidth,
    required double videoHeight,
    required double durationSeconds,
  }) async {
    List<double> centersX = [];
    
    // 1. Core Logic: Extract frame frames as PNGs at a low frequency to prevent CPU overload.
    // We extract frames every 200ms (5 frames per second) into a temp folder.
    final tempDir = Directory.systemTemp.createTempSync('frames');
    final frameCmd = '-i "${videoFile.path}" -r 5 "${tempDir.path}/frame_%04d.png"';
    
    // (Execute Frame Extraction via FFmpegKit)
    
    final List<FileSystemEntity> frames = tempDir.listSync().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    double lastKnownX = videoWidth / 2; // Default starting position is standard middle crop

    for (var frameFile in frames) {
      if (frameFile is File) {
        final inputImage = InputImage.fromFile(frameFile);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (faces.isNotEmpty) {
          // If multiple faces are detected, track the largest face (most likely the focal speaker)
          faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
          
          final mainFace = faces.first;
          // Calculate center horizontal coordinates of the face
          lastKnownX = mainFace.boundingBox.left + (mainFace.boundingBox.width / 2);
        }
        centersX.add(lastKnownX);
      }
    }

    // Cleanup extracted temp frame images immediately to conserve storage
    tempDir.deleteSync(recursive: true);
    
    // Apply smoothing filter to eliminate rapid jitter/camera shifts
    return _applyLowPassFilter(centersX, alpha: 0.2);
  }

  /// Low Pass Filter smoothing algorithm
  List<double> _applyLowPassFilter(List<double> raw, {required double alpha}) {
    if (raw.isEmpty) return [];
    List<double> smoothed = [raw.first];
    for (int i = 1; i < raw.length; i++) {
      smoothed.add(alpha * raw[i] + (1 - alpha) * smoothed[i - 1]);
    }
    return smoothed;
  }

  void dispose() {
    _faceDetector.close();
  }
}
```

---

### D. `CaptionService` (`lib/services/caption_service.dart`)
Compiles structured JSON transcript models into highly-customized Advanced SubStation Alpha (`.ass`) subtitles to support CapCut-style rich text.

```dart
import 'dart:io';

class CaptionService {
  /// Converts Gemini segment transcripts to raw ASS styled subtitles
  Future<File> generateAssSubtitles({
    required Map<String, dynamic> geminiTranscript,
    required String targetFilePath,
  }) async {
    final buffer = StringBuffer();

    // 1. Setup Standard ASS Styles Header
    buffer.write('''[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Impact,80,&H00FFFFFF,&H0000FFFF,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,6,2,2,10,10,960,1
''');
    // Alignment 2 is bottom center. MarginV 960 places text exact middle of a 1920 vertical canvas.
    
    buffer.write('\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n');

    final List<dynamic> segments = geminiTranscript['segments'];

    for (var seg in segments) {
      final int startMs = seg['start_time_ms'];
      final int endMs = seg['end_time_ms'];
      final String text = seg['text'];
      final List<dynamic> keywords = seg['keywords'] ?? [];

      final String startTimeStr = _formatAssTime(startMs);
      final String endTimeStr = _formatAssTime(endMs);

      // Apply keyword style replacements
      // Primary color is White (&H00FFFFFF). Active keyword is Cyan (&H00FFFF00)
      String processedText = text;
      for (var kw in keywords) {
        if (kw is String && kw.isNotEmpty) {
          // Case-insensitive search & replacement with ASS colour tags
          final reg = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false);
          processedText = processedText.replaceAllMapped(reg, (m) => "{\\c&H00FFFF&}${m.group(0)}{\\c}");
        }
      }

      buffer.writeln('Dialogue: 0,$startTimeStr,$endTimeStr,Default,,0,0,0,,$processedText');
    }

    final file = File(targetFilePath);
    await file.writeAsString(buffer.toString());
    return file;
  }

  String _formatAssTime(int ms) {
    final int hours = ms ~/ 3600000;
    final int minutes = (ms % 3600000) ~/ 60000;
    final int seconds = (ms % 60000) ~/ 1000;
    final int centiseconds = (ms % 1000) ~/ 10;

    final hh = hours.toString().padLeft(1, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    final cs = centiseconds.toString().padLeft(2, '0');

    return '$hh:$mm:$ss.$cs';
  }
}
```

---

### E. `YouTubeService` (`lib/services/youtube_service.dart`)
Evaluates YouTube download approaches. We recommend **`youtube_explode_dart`** for 100% pure-Dart cross-platform compilation, bypassing complex native JNI bindings or Python-in-Android runtime packs that often crash in CI pipelines.

```dart
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Validate link
  bool isValidUrl(String url) {
    try {
      VideoId.parseVideoId(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Downloads both streams (video + audio) and muxes them locally via FFmpeg
  Future<File> downloadYouTubeVideo({
    required String url,
    required String outputDirectory,
    required Function(double progress) onProgress,
  }) async {
    final videoId = VideoId.parseVideoId(url);
    final video = await _yt.videos.get(videoId);

    // Get stream manifest
    final manifest = await _yt.videos.streams.getManifest(videoId);
    
    // Choose highest quality video stream (e.g. 1080p, 720p)
    final videoStreamInfo = manifest.videoOnly.withHighestBitrate();
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

    final videoFile = File('$outputDirectory/${videoId.value}_temp_v.mp4');
    final audioFile = File('$outputDirectory/${videoId.value}_temp_a.mp4');

    // Download Video Stream
    await _downloadStream(videoStreamInfo, videoFile, (p) => onProgress(p * 0.7)); // 70% of loading bar
    
    // Download Audio Stream
    await _downloadStream(audioStreamInfo, audioFile, (p) => onProgress(0.7 + (p * 0.3))); // remaining 30%

    // Mux files together using FFmpeg (fast copy codecs)
    final muxedFile = File('$outputDirectory/${videoId.value}_full.mp4');
    
    // Mux command
    // -c:v copy -c:a copy processes instantly with 0 re-encoding CPU overhead!
    final cmd = '-i "${videoFile.path}" -i "${audioFile.path}" -c:v copy -c:a copy -y "${muxedFile.path}"';
    
    // (Run via FFmpegKit)
    
    // Cleanup temporary stream fragments
    if (await videoFile.exists()) await videoFile.delete();
    if (await audioFile.exists()) await audioFile.delete();

    return muxedFile;
  }

  Future<void> _downloadStream(
    StreamInfo streamInfo,
    File file,
    Function(double progress) progressCallback,
  ) async {
    final stream = _yt.videos.streams.get(streamInfo);
    final fileStream = file.openWrite(mode: FileMode.writeOnly);

    var len = streamInfo.size.totalBytes;
    var count = 0;

    await for (final data in stream) {
      count += data.length;
      progressCallback(count / len);
      fileStream.add(data);
    }
    await fileStream.flush();
    await fileStream.close();
  }

  void dispose() {
    _yt.close();
  }
}
```

---

## 6. Detailed Dynamic / Smart Cropping Algorithm

Converting horizontal videos (16:9) to standard high-engagement vertical formats (9:16) usually cuts off moving action. We solve this on-device by executing a tracking algorithm.

### Two-Tier Cropping Architecture:

#### Option A: Average Focal Center Smart Crop (Recommended Baseline)
- High performance, 100% stable, 0 jitter.
- **Algorithm**:
  1. ML Kit samples coordinates of the active face across 30 coordinates during the clip segment.
  2. Compute the mathematical **median (or mean)** x-coordinate: `avg_x = sum(x) / total_samples`.
  3. Determine the static bounding box offset:
     - Output height: `1080` (original size).
     - Output crop width: `1080 * 9 / 16 = 607.5` px.
     - Frame offset: `crop_x = avg_x - (607.5 / 2)`.
     - Bounds check constraint: `crop_x = clamp(crop_x, 0, original_width - 607.5)`.
  4. Build static FFmpeg command: `crop=607.5:1080:crop_x:0`.

#### Option B: Real-Time Dynamic Motion Crop (Cinematic Pans)
- If dynamic tracking is chosen, we implement cinematic pans rather than rapid screen jumps.
- **Dynamic Crop Command Generation**:
  We generate an FFmpeg command using the **`crop`** filter's evaluation variables `t` (time in seconds).
  
  We create a coordinate string mapped to time:
  - If we sampled at 5fps, we have coordinate values at intervals of `0.2` seconds.
  - We generate an FFmpeg command using the **`crop`** filter's evaluation variables `t` (time in seconds).
  
  **The mathematical expression format:**
  `crop=607:1080:'if(lt(t,0.2),X0,if(lt(t,0.4),X1,if(lt(t,0.6),X2,X3)))':0`
  
  Where `X0, X1, X2...` are the computed, smoothed coordinates of the face bounding box at those specific time intervals. Because the coordinates have been filtered through our **Low Pass Filter (`alpha=0.2`)**, the movement creates a beautiful, smooth camera pan effect.

---

## 7. GitHub Actions CI/CD Configuration

To accommodate compiling heavy Gradle release files on a constrained 4GB RAM local host laptop, this GitHub Actions workflow completely automates the release process. 

Simply push to `main` branch to trigger an automatic release and artifact download link.

Write this file to `.github/workflows/build.yml`:

```yaml
name: Build Android Release APK

on:
  push:
    branches:
      - main
  workflow_dispatch: # Allows manual trigger of builds

jobs:
  build:
    name: Build & Release Release APK
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Set up Java Development Kit (JDK)
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.6'
          channel: 'stable'
          cache: true

      - name: Install Project Dependencies
        run: flutter pub get

      - name: Run Build Runner (Hive Adapters Generation)
        run: flutter pub run build_runner build --delete-conflicting-outputs

      # Unsigned release APK for quick debug testing.
      - name: Build Release APK
        run: flutter build apk --release --no-shrink

      - name: Upload APK Artifact
        uses: actions/upload-artifact@v4
        with:
          name: clippit-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

---

## 8. Phased Implementation Timeline & Milestones

| Milestone | Target Duration | Deliverables |
|---|---|---|
| **Phase 1: Foundation & Layout** | Days 1–3 | Setup Flutter environment; configure dark Theme palette; implement responsive dashboard layout, local settings panel (`shared_preferences`), and SQLite/Hive initializers. |
| **Phase 2: YouTube Interceptor** | Days 4–5 | Connect `youtube_explode_dart` stream downloader. Mux downloaded audio and video segments back to localized cache storage. Check file hashes. |
| **Phase 3: AI Integration** | Days 6–8 | Implement `GeminiService` video upload workflows. Connect structured prompt parsers (Pass 1 highlight JSON schema with dynamic model parameters). Implement highlight collection dashboard UI. |
| **Phase 4: FFmpeg Services** | Days 9–10 | Construct FFmpeg trimming commands and render pipelines via `ffmpeg_kit_flutter_new`. Connect clip-relative Pass 2 transcription parser (`CaptionService`) and compile into custom `.ass` format. |
| **Phase 5: Face Tracker & Render** | Days 11–12 | Connect on-device ML Kit Face Detector. Run coordinate-smoothing algorithm. Integrate dynamic crop matrix in FFmpeg and burn-in overlay subtitles. |
| **Phase 6: Presets, Share, & CI/CD** | Days 13–14 | Establish export aspect ratio presets (Shorts, TikTok, Reels). Construct CI/CD workflow pipeline for remote APK building. Run system-level tests. |

---

## 9. Critical Pitfalls, Edge Cases, & Mitigations

### 1. Gemini Request Limits & Free-Tier Throttling
- *Risk*: The Gemini Free API tier has limits (15 RPM - requests per minute, 1500 RPD - requests per day, and 1 million TPM - tokens per minute).
- *Mitigations*:
  - **Aggressive Caching**: Hive saves prompt evaluations. If the same video URL is scanned multiple times, it triggers 0 API calls.
  - **Sequential Throttling**: The pipeline never executes multiple heavy calls in parallel. In-app loading animations actively state status to the user.
  - **Pass 2 Compression**: The clip is trimmed *before* transcription. Analyzing a 1-minute clip costs less than 1% of the tokens required for a full-length video.

### 2. High Memory Storage Accumulation
- *Risk*: Multiple high-definition stream downloads will quickly deplete device memory.
- *Mitigations*:
  - Implement dynamic cleanup hooks on pipeline failure or successful export.
  - Clear all temporary folders (`/temp/frames`, `.temp_a.mp4`, `.temp_v.mp4`) inside the storage controller class immediately.

### 3. YouTube Layout/Signature Updates
- *Risk*: YouTube changes their streaming architectures occasionally, breaking extraction APIs.
- *Mitigations*:
  - Using pure Dart `youtube_explode_dart` enables rapid dependency updates (the maintainers generally push a patch package within hours of a major breaking YouTube update).
  - Include an easy "Update App" alert on the dashboard to warn user of needed package versions.
