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
      final logMessages = logs.map((l) => l.getMessage()).join("\n");
      throw Exception('FFmpeg Trim Failed:\n$logMessages');
    }
  }

  /// Muxes separate video and audio streams into a single container without re-encoding
  Future<File> muxStreams({
    required File videoFile,
    required File audioFile,
    required String targetPath,
  }) async {
    final cmd = '-i "${videoFile.path}" -i "${audioFile.path}" -c:v copy -c:a copy -y "$targetPath"';
    
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      return File(targetPath);
    } else {
      final logs = await session.getLogs();
      final logMessages = logs.map((l) => l.getMessage()).join("\n");
      throw Exception('FFmpeg Muxing Failed:\n$logMessages');
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
      final logMessages = logs.map((l) => l.getMessage()).join("\n");
      throw Exception('FFmpeg Render Failed:\n$logMessages');
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
