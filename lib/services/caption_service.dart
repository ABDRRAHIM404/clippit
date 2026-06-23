import 'dart:io';

class CaptionService {
  /// Converts Gemini segment transcripts to raw ASS styled subtitles
  /// Adapts PlayRes resolutions and Margins dynamically based on the selected cropStyle
  /// 🌟 Upgraded to support dynamic fontFamilies and custom active keyword highlight colors!
  Future<File> generateAssSubtitles({
    required Map<String, dynamic> geminiTranscript,
    required String targetFilePath,
    required String cropStyle,       // 'Keep 16:9', '9:16', '1:1', '4:5'
    required String fontFamily,      // 'sans-serif-condensed', 'sans-serif', 'serif', 'monospace'
    required String highlightColor,  // 'Electric Cyan', 'Electric Yellow', 'Neon Green'
  }) async {
    final buffer = StringBuffer();

    // 1. Resolve dynamic resolutions and vertical margin placement
    int resX = 1080;
    int resY = 1920;
    int marginV = 360; // 360px up from bottom for portrait 9:16 (Perfect bottom-third safe zone!)

    if (cropStyle == 'Keep 16:9') {
      resX = 1920;
      resY = 1080;
      marginV = 120; // Safe bottom placement for landscape 16:9
    } else if (cropStyle == '1:1') {
      resX = 1080;
      resY = 1080;
      marginV = 180; // Safe bottom placement for square 1:1
    } else if (cropStyle == '4:5') {
      resX = 1080;
      resY = 1350;
      marginV = 220; // Safe bottom placement for social 4:5
    }

    // 2. Resolve native ASS hex BGR color tag for key words
    String colorTag = '&H0000FFFF&'; // Default Electric Yellow
    if (highlightColor == 'Electric Cyan') colorTag = '&H00FFFF00&';
    if (highlightColor == 'Neon Green') colorTag = '&H0000FF00&';

    // 3. Setup Standard ASS Styles Header 
    // - Incorporates your dynamically selected Font Family!
    // - Bumped Fontsize to 84 for professional legibility
    buffer.write('''[Script Info]
ScriptType: v4.00+
PlayResX: $resX
PlayResY: $resY
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,$fontFamily,84,&H00FFFFFF,$colorTag,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,5,1.5,$marginV,10,10,10,1
''');
    // Alignment 2 is Bottom-Center.
    
    buffer.write('\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n');

    final List<dynamic> segments = geminiTranscript['segments'] ?? [];

    for (var seg in segments) {
      final int startMs = seg['start_time_ms'] ?? 0;
      final int endMs = seg['end_time_ms'] ?? 0;
      final String text = seg['text'] ?? '';
      final List<dynamic> keywords = seg['keywords'] ?? [];

      final String startTimeStr = _formatAssTime(startMs);
      final String endTimeStr = _formatAssTime(endMs);

      // Apply dynamic keyword highlight color tags
      String processedText = text;
      for (var kw in keywords) {
        if (kw is String && kw.isNotEmpty) {
          // Case-insensitive search & replacement with ASS colour tags
          final reg = RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false);
          processedText = processedText.replaceAllMapped(reg, (m) => "{\\c$colorTag}${m.group(0)}{\\c}");
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
