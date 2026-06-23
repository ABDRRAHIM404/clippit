import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'ffmpeg_service.dart';

class YouTubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Validate YouTube link
  bool isValidUrl(String url) {
    try {
      VideoId.parseVideoId(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Extracts the clean alphanumeric YouTube Video ID as a String
  String extractVideoId(String url) {
    final parsed = VideoId.parseVideoId(url);
    return parsed?.toString() ?? '';
  }

  /// Downloads a pre-muxed stream (contains both video and audio)
  /// Upgraded with strict timeouts (15 seconds) to prevent silent hangs and report errors clearly!
  Future<File> downloadAndMuxYouTubeVideo({
    required String url,
    required String outputDirectory,
    required FFmpegService ffmpegService,
    required Function(double progress) onProgress,
  }) async {
    try {
      final parsedId = VideoId.parseVideoId(url);
      if (parsedId == null) throw Exception('Invalid YouTube URL format.');
      final String videoIdString = parsedId.toString();
      
      // 🌟 Added strict timeout to getManifest call
      final manifest = await _yt.videos.streams.getManifest(parsedId).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Failed to retrieve video metadata from YouTube (Connection Timed Out).'),
      );
      
      final muxedStreamInfo = manifest.muxed.withHighestBitrate();
      final muxedFile = File('$outputDirectory/${videoIdString}_full.mp4');

      // If muxed file already exists, return it immediately
      if (await muxedFile.exists() && await muxedFile.length() > 100000) {
        onProgress(1.0);
        return muxedFile;
      }

      // Download the unified stream directly (with strict chunked timeouts)
      await _downloadStream(
        muxedStreamInfo, 
        muxedFile, 
        (p) => onProgress(p),
      );
      
      onProgress(1.0);
      return muxedFile;
    } catch (e) {
      throw Exception('YouTube Stream Extraction Failed: $e');
    }
  }

  /// Downloads a single chunked media stream segment with progress call hooks
  Future<void> _downloadStream(
    StreamInfo streamInfo,
    File file,
    Function(double progress) progressCallback,
  ) async {
    final stream = _yt.videos.streams.get(streamInfo);
    final fileStream = file.openWrite(mode: FileMode.writeOnly);

    var totalBytes = streamInfo.size.totalBytes;
    var downloadedBytes = 0;

    try {
      // 🌟 Listen to stream and apply timeout to individual data packets
      final subscription = stream.timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) {
          sink.addError(TimeoutException('YouTube stream stalled. Data packet retrieval timed out.'));
        },
      );

      await for (final data in subscription) {
        downloadedBytes += data.length;
        progressCallback(downloadedBytes / totalBytes);
        fileStream.add(data);
      }
      await fileStream.flush();
    } finally {
      await fileStream.close();
    }
  }

  void dispose() {
    _yt.close();
  }
}
