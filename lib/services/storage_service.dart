import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class StorageService {
  /// Gets a safe local application documents directory to persist rendered clips
  Future<Directory> getAppLibraryDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  /// Gets a safe temporary directory to download video chunks & frames
  Future<Directory> getAppTempDirectory() async {
    return await getTemporaryDirectory();
  }

  /// Generates a unique, memory-safe SHA-256 hash of a local video file.
  /// Reads the file in 64KB chunks to keep the memory footprint extremely low (near 0MB RAM).
  Future<String> calculateFileHash(File file) async {
    if (!await file.exists()) {
      throw Exception('File does not exist for hash computation.');
    }

    final ds = sha256.startChunkedConversion(accumulated);
    final stream = file.openRead();
    
    await for (final chunk in stream) {
      ds.add(chunk);
    }
    
    ds.close();
    return ds.accumulated.toString();
  }

  /// Clear all cached chunks and media pieces inside the temp folder to save space
  Future<void> clearAllTemporaryFiles() async {
    try {
      final tempDir = await getAppTempDirectory();
      if (await tempDir.exists()) {
        final entities = tempDir.listSync(recursive: true);
        for (var entity in entities) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      print('Warning: Failed to clean temporary directories: $e');
    }
  }
}
