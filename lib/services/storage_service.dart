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
  /// Uses direct Stream Binding to hash the file chunk-by-chunk under the hood,
  /// keeping RAM usage at practically 0MB.
  Future<String> calculateFileHash(File file) async {
    if (!await file.exists()) {
      throw Exception('File does not exist for hash computation.');
    }

    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Item 7: Guaranteed automatic clean up of all temporary files inside the cache directory
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

  /// Item 7: Fallback cleanup running on startup to catch any leftover files from crashed/halted sessions
  Future<void> cleanLeftoverTempFilesOnStartup() async {
    try {
      final tempDir = await getAppTempDirectory();
      if (await tempDir.exists()) {
        final entities = tempDir.listSync();
        for (var entity in entities) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}
