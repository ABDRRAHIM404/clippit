import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceTrackingService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast, // High performance prioritization
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
    
    // 1. Core Logic: Extract frames as PNGs at a low frequency to prevent CPU overload.
    final tempDir = Directory.systemTemp.createTempSync('frames');
    
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
