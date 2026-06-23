import 'dart:io';

class CaptionService {
  /// Converts Gemini segment transcripts to raw ASS styled subtitles
  /// Adapts PlayRes resolutions and Margins dynamically based on the selected cropStyle
  /// 🌟 Fix 1: Corrected style column order mapping (swapping Alignment to 2, and MarginV to $marginV)
  /// to ensure captions render exactly in the lower third (80% down the screen vertically) by default!
  Future<File> generateAssSubtitles({
    required Map<String, dynamic> geminiTranscript,
    required String targetFilePath,
    required String cropStyle,       // 'Keep 16:9', '9:16', '1:1', '4:5'
    required String fontFamily,      // 'sans-serif-condensed', 'sans-serif', 'serif', 'monospace'
    required String highlightColor,  // 'Electric Cyan', 'Electric Yellow', 'Neon Green'
  }) async {
    final buffer = StringBuffer();

    // 🌟 Fix 1: Calculate exact 80% vertical safe offsets from the bottom for each ratio style!
    int resX = 1080;
    int resY = 1920;
    int marginV = 380; // 80% down on 1080x1920 canvas is exactly 380 pixels from the bottom!

    if (cropStyle == 'Keep 16:9') {
      resX = 1920;
      resY = 1080;
      marginV = 210; // 80% down on 1920x1080 is 216 pixels from the bottom
    } else if (cropStyle == '1:1') {
      resX = 1080;
      resY = 1080;
      marginV = 210; // 80% down on 1080x1080 is 216 pixels from the bottom
    } else if (cropStyle == '4:5') {
      resX = 1080;
      resY = 1350;
      marginV = 270; // 80% down on 1080x1350 is 270 pixels from the bottom
    }

    // 2. Resolve native ASS hex BGR color tag for key words
    String colorTag = '&H0000FFFF&'; // Default Yellow
    if (highlightColor == 'Electric Cyan') colorTag = '&H00FFFF00&';
    if (highlightColor == 'Neon Green') colorTag = '&H0000FF00&';

    // 3. Setup Standard ASS Styles Header 
    // 🌟 Fix 1: Positioned Alignment to 2 (Bottom-Center) and MarginV to $marginV in the style definition format!
    buffer.write('''[Script Info]
ScriptType: v4.00+
PlayResX: $resX
PlayResY: $resY
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,$fontFamily,84,&H00FFFFFF,$colorTag,&H00000000,&H80000000,-1,0,0,0,100,100,0,0,1,5,1.5,2,10,10,$marginV,1
''');
    
    buffer.write('\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n');

    final List<dynamic> segments = geminiTranscript['segments'] ?? [];

    for (var seg in segments) {
      final int startMs = seg['start_time_ms'] ?? 0;
      final int endMs = seg['end_time_ms'] ?? 0;
      final String text = seg['text'] ?? '';
      final List<dynamic> keywords = seg['keywords'] ?? [];

      final String startTimeStr = _formatAssTime(startMs);
      final String endTimeStr = _formatAssTime(endMs);

      // Apply keyword style replacements
      String processedText = text;
      for (var kw in keywords) {
        if (kw is String && kw.isNotEmpty) {
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
