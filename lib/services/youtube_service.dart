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
    // On different versions of youtube_explode_dart, parseVideoId might return String or VideoId.
    // We handle both safely by converting to String.
    return parsed?.toString() ?? '';
  }

  /// Downloads both high-resolution streams (video + audio) and muxes them locally via FFmpeg
  Future<File> downloadAndMuxYouTubeVideo({
    required String url,
    required String outputDirectory,
    required FFmpegService ffmpegService,
    required Function(double progress) onProgress,
  }) async {
    final parsedId = VideoId.parseVideoId(url);
    if (parsedId == null) throw Exception('Invalid YouTube URL');
    final String videoIdString = parsedId.toString();
    
    // Get stream manifest
    final manifest = await _yt.videos.streams.getManifest(parsedId);
    
    // Choose highest quality video-only stream (e.g. 1080p, 720p)
    final videoStreamInfo = manifest.videoOnly.withHighestBitrate();
    // Choose highest quality audio-only stream
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

    final tempVideoFile = File('$outputDirectory/${videoIdString}_temp_v.mp4');
    final tempAudioFile = File('$outputDirectory/${videoIdString}_temp_a.mp4');
    final muxedFile = File('$outputDirectory/${videoIdString}_full.mp4');

    // If muxed file already exists, return it immediately (caching stream downloads)
    if (await muxedFile.exists() && await muxedFile.length() > 100000) {
      onProgress(1.0);
      return muxedFile;
    }

    try {
      // 1. Download Video Stream (0% to 70% of loading sequence)
      await _downloadStream(
        videoStreamInfo, 
        tempVideoFile, 
        (p) => onProgress(p * 0.70),
      );
      
      // 2. Download Audio Stream (70% to 95% of loading sequence)
      await _downloadStream(
        audioStreamInfo, 
        tempAudioFile, 
        (p) => onProgress(0.70 + (p * 0.25)),
      );

      // 3. Mux streams together via stream copying (instantaneous)
      onProgress(0.97);
      
      // Execute muxing via our FFmpegService wrapper
      await ffmpegService.muxStreams(
        videoFile: tempVideoFile,
        audioFile: tempAudioFile,
        targetPath: muxedFile.path,
      );
      
      onProgress(1.0);
      return muxedFile;
    } finally {
      // 4. Always cleanup separate stream pieces to preserve disk storage
      try {
        if (await tempVideoFile.exists()) await tempVideoFile.delete();
        if (await tempAudioFile.exists()) await tempAudioFile.delete();
      } catch (e) {
        print('Warning: Failed to delete temporary stream fragments: $e');
      }
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
      await for (final data in stream) {
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
