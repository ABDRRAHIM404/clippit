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
