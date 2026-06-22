import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_colors.dart';
import '../models/clip_suggestion.dart';

class EditScreen extends StatefulWidget {
  final File sourceVideoFile;
  final ClipSuggestion initialSuggestion;
  final Function({
    required double startSeconds,
    required double endSeconds,
    required bool enableCrop,
    required bool enableCaptions,
    required String selectedLanguage,
  }) onExportTriggered;

  const EditScreen({
    super.key,
    required this.sourceVideoFile,
    required this.initialSuggestion,
    required this.onExportTriggered,
  });

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late VideoPlayerController _playerController;
  late double _startSeconds;
  late double _endSeconds;
  late double _maxDuration;

  bool _enableCrop = true;
  bool _enableCaptions = true;
  String _selectedLanguage = 'English';
  bool _isPlayerInitialized = false;

  final List<String> _languages = ['English', 'Spanish', 'French', 'German', 'Portuguese', 'Japanese'];

  @override
  void initState() {
    super.initState();
    _startSeconds = widget.initialSuggestion.startTimeSeconds;
    _endSeconds = widget.initialSuggestion.endTimeSeconds;
    
    _initVideoPlayer();
  }

  Future<void> _initVideoPlayer() async {
    _playerController = VideoPlayerController.file(widget.sourceVideoFile);
    try {
      await _playerController.initialize();
      setState(() {
        _maxDuration = _playerController.value.duration.inSeconds.toDouble();
        _isPlayerInitialized = true;
        
        // Seek to suggested starting point
        _playerController.seekTo(Duration(seconds: _startSeconds.toInt()));
      });
    } catch (e) {
      print('Error loading video player: $e');
    }
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

  void _seekTo(double seconds) {
    if (_isPlayerInitialized) {
      _playerController.seekTo(Duration(seconds: seconds.toInt()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double clipDuration = _endSeconds - _startSeconds;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fine-Tune & Adjust'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              setState(() {
                _startSeconds = widget.initialSuggestion.startTimeSeconds;
                _endSeconds = widget.initialSuggestion.endTimeSeconds;
                _seekTo(_startSeconds);
              });
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildVideoPlayerPreview(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimelineScrubberHeader(clipDuration),
                  const SizedBox(height: 12),
                  _buildRangeSlider(),
                  const SizedBox(height: 28),
                  _buildCustomizationToggles(),
                  const SizedBox(height: 32),
                  _buildRenderButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayerPreview() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: _isPlayerInitialized
            ? Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_playerController),
                  // Visual 9:16 vertical crop guide overlay if crop is enabled
                  if (_enableCrop)
                    Container(
                      width: MediaQuery.of(context).size.width * (9 / 16) * (9 / 16), // scaled relative vertical box
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.accentNeon.withOpacity(0.8), width: 1.5),
                        color: Colors.transparent,
                      ),
                    ),
                  
                  // Simple play/pause button overlay
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
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _playerController.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.primaryLight),
              ),
      ),
    );
  }

  Widget _buildTimelineScrubberHeader(double clipDuration) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Timeline Cut Segment',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: clipDuration > 75.0 ? AppColors.error.withOpacity(0.15) : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: clipDuration > 75.0 ? AppColors.error : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            '${clipDuration.toStringAsFixed(1)}s / 75s max',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: clipDuration > 75.0 ? AppColors.error : AppColors.accentNeon,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRangeSlider() {
    if (!_isPlayerInitialized) {
      return const SizedBox(height: 40);
    }

    return Column(
      children: [
        RangeSlider(
          values: RangeValues(_startSeconds, _endSeconds),
          min: 0.0,
          max: _maxDuration,
          divisions: _maxDuration.toInt(),
          activeColor: AppColors.primaryLight,
          inactiveColor: AppColors.border,
          labels: RangeLabels(
            _formatTimeSeconds(_startSeconds),
            _formatTimeSeconds(_endSeconds),
          ),
          onChanged: (RangeValues values) {
            setState(() {
              _startSeconds = values.start;
              _endSeconds = values.end;
            });
          },
          onChangeEnd: (RangeValues values) {
            // Seek player to preview start offset of selected range
            _seekTo(values.start);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Start: ${_formatTimeSeconds(_startSeconds)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              'End: ${_formatTimeSeconds(_endSeconds)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildCustomizationToggles() {
    return Column(
      children: [
        // 9:16 Vertical Crop Toggle
        _buildToggleCard(
          icon: Icons.crop_portrait,
          title: 'Vertical Auto-Crop (9:16)',
          description: 'Leverage Google ML Kit to track the speaker face.',
          value: _enableCrop,
          onChanged: (val) => setState(() => _enableCrop = val),
        ),
        const SizedBox(height: 16),

        // Captions Enablement Toggle
        _buildToggleCard(
          icon: Icons.subtitles,
          title: 'Burn-In Captions',
          description: 'Add styled keyword-highlighted captions to the clip.',
          value: _enableCaptions,
          onChanged: (val) => setState(() => _enableCaptions = val),
        ),
        
        // Language Picker Panel (Slides out if subtitles are enabled)
        if (_enableCaptions) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Translation Language',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  DropdownButton<String>(
                    value: _selectedLanguage,
                    underline: const SizedBox(),
                    dropdownColor: AppColors.surface,
                    items: _languages.map((String lang) {
                      return DropdownMenuItem<String>(
                        value: lang,
                        child: Text(lang, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (String? val) {
                      if (val != null) setState(() => _selectedLanguage = val);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleCard({
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryLight, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: AppColors.success,
              inactiveThumbColor: AppColors.textMuted,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRenderButton() {
    final double clipDuration = _endSeconds - _startSeconds;
    final bool isTooLong = clipDuration > 75.0;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isTooLong
            ? null
            : () {
                widget.onExportTriggered(
                  startSeconds: _startSeconds,
                  endSeconds: _endSeconds,
                  enableCrop: _enableCrop,
                  enableCaptions: _enableCaptions,
                  selectedLanguage: _selectedLanguage,
                );
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isTooLong ? AppColors.surfaceLight : AppColors.primary,
        ),
        child: Text(
          isTooLong ? 'Clip Too Long (Max 75s)' : 'Cut & Render Highlight',
        ),
      ),
    );
  }

  String _formatTimeSeconds(double totalSeconds) {
    final int mins = totalSeconds ~/ 60;
    final int secs = (totalSeconds % 60).toInt();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
