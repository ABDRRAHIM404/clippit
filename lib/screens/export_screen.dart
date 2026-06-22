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

  Future<void> _shareClip(String platformName) async {
    // Uses the official share_plus package to trigger native sharing trays
    final XFile file = XFile(widget.renderedClipFile.path);
    await Share.shareXFiles(
      [file],
      text: 'Check out this epic highlight from "${widget.clipTitle}"! Generated via #Clippit #AI',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Render Complete'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: widget.onReturnHome,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            _buildVerticalVideoPreview(),
            const SizedBox(height: 28),
            _buildPlatformPresetSelectors(),
            const SizedBox(height: 28),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalVideoPreview() {
    return Container(
      height: 380,
      width: 380 * (9 / 16), // Force 9:16 vertical box
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
          ? Stack(
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
            )
          : const Center(
              child: CircularProgressIndicator(color: AppColors.accentNeon),
            ),
    );
  }

  Widget _buildPlatformPresetSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Export Presets',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildPresetCard(
              icon: Icons.music_note,
              label: 'TikTok',
              color: const Color(0xFFFE2C55),
              onTap: () => _shareClip('TikTok'),
            ),
            _buildPresetCard(
              icon: Icons.video_library_rounded,
              label: 'YouTube Shorts',
              color: const Color(0xFFFF0000),
              onTap: () => _shareClip('YouTube Shorts'),
            ),
            _buildPresetCard(
              icon: Icons.camera_alt,
              label: 'Instagram Reels',
              color: const Color(0xFFE1306C),
              onTap: () => _shareClip('Instagram Reels'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 20),
            label: const Text('Open System Share Sheet'),
            onPressed: () => _shareClip('Generic'),
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
