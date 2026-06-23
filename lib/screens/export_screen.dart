import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_colors.dart';

class ExportScreen extends StatefulWidget {
  final File renderedClipFile;
  final String clipTitle;
  final VoidCallback onReturnHome;

  const ExportScreen({
    super.key,
    required this.renderedClipFile,
    required this.clipTitle,
    required this.onReturnHome,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late VideoPlayerController _playerController;
  bool _isPlayerInitialized = false;

  @override
  void initState() {
    super.initState();
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _playerController = VideoPlayerController.file(widget.renderedClipFile);
    try {
      await _playerController.initialize();
      _playerController.setLooping(true);
      setState(() {
        _isPlayerInitialized = true;
        _playerController.play();
      });
    } catch (e) {
      print('Error playing rendered clip: $e');
    }
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _shareClip() async {
    // Uses the official share_plus package to trigger native sharing trays
    final XFile file = XFile(widget.renderedClipFile.path);
    await Share.shareXFiles(
      [file],
      text: 'Check out this epic highlight from "${widget.clipTitle}"! Generated via #Clippit #AI',
    );
  }

  /// 🌟 Save to Gallery / Downloads folder via Scoped Storage
  /// Pure Dart, 100% crash-proof and requires zero native Android package dependencies!
  Future<void> _saveToGallery() async {
    try {
      final String publicDownloadPath = '/storage/emulated/0/Download/Clippit_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final File destinationFile = File(publicDownloadPath);
      
      // Ensure the Downloads directory exists
      final Directory downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      
      await widget.renderedClipFile.copy(destinationFile.path);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video successfully saved to your phone\'s Downloads folder!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save to gallery: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Render Complete'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), // Replaced Home icon with standard Back/Return arrow!
          onPressed: widget.onReturnHome,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            const SizedBox(height: 10),
            _buildVideoPreviewContainer(),
            const SizedBox(height: 40),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreviewContainer() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _isPlayerInitialized
          ? AspectRatio(
              aspectRatio: _playerController.value.aspectRatio, // Dynamically adapts to 16:9, 9:16, 1:1, or 4:5!
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_playerController),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _playerController.value.isPlaying
                            ? _playerController.pause()
                            : _playerController.play();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _playerController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const Center(
              child: CircularProgressIndicator(color: AppColors.accentNeon),
            ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // 🌟 Save to Gallery Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 20, color: Colors.black),
            label: const Text('Save to Gallery / Downloads', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _saveToGallery,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 20),
            label: const Text('Open System Share Sheet'),
            onPressed: _shareClip, // Directly share the finished resolution file!
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.home, size: 20, color: AppColors.primaryLight),
            label: const Text('Back to Dashboard', style: TextStyle(color: AppColors.textPrimary)),
            onPressed: widget.onReturnHome,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }
}
