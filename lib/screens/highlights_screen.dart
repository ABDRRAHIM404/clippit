import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/clip_suggestion.dart';

class HighlightsScreen extends StatelessWidget {
  final List<ClipSuggestion> suggestions;
  final String sourceTitle;
  final Function(ClipSuggestion selectedClip) onClipSelected;

  const HighlightsScreen({
    super.key,
    required this.suggestions,
    required this.sourceTitle,
    required this.onClipSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Sort suggestions by highest virality score first to push elite content to top
    final sortedSuggestions = List<ClipSuggestion>.from(suggestions)
      ..sort((a, b) => b.viralityScore.compareTo(a.viralityScore));

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Suggested Highlights'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSourceVideoHeader(),
          Expanded(
            child: sortedSuggestions.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: sortedSuggestions.length,
                    itemBuilder: (context, index) {
                      final clip = sortedSuggestions[index];
                      return _buildClipCard(context, clip, index);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceVideoHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.video_library, color: AppColors.textSecondary, size: 16),
              const SizedBox(width: 6),
              Text(
                'Source Video'.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sourceTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.psychology, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'No Highlights Found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gemini scanned the file but could not identify segments matching the length constraints.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClipCard(BuildContext context, ClipSuggestion clip, int index) {
    final double duration = clip.endTimeSeconds - clip.startTimeSeconds;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onClipSelected(clip),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Card Image Header / Colored Indicator
              Stack(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.surfaceLight, AppColors.surface],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.movie,
                        size: 40,
                        color: AppColors.textMuted.withOpacity(0.5),
                      ),
                    ),
                  ),
                  
                  // Duration Badge (Bottom Right)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatDuration(duration),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),

                  // Virality Score Badge (Top Right)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getViralityColor(clip.viralityScore),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _getViralityColor(clip.viralityScore).withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            color: _getViralityColor(clip.viralityScore),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${clip.viralityScore}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _getViralityColor(clip.viralityScore),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Segment Index Tag (Top Left)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Moment #${index + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Text Content Area
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Timeframe: ${_formatTime(clip.startTimeSeconds)} - ${_formatTime(clip.endTimeSeconds)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accentNeon,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      clip.reason,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Select and Edit'.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryLight,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: AppColors.primaryLight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getViralityColor(int score) {
    if (score >= 85) return AppColors.accentWarm; // High-fire yellow
    if (score >= 65) return AppColors.accentNeon; // Good cyan
    return AppColors.textSecondary;               // Default muted gray
  }

  String _formatDuration(double seconds) {
    final int mins = seconds ~/ 60;
    final int secs = (seconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String _formatTime(double totalSeconds) {
    final int mins = totalSeconds ~/ 60;
    final int secs = (totalSeconds % 60).toInt();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
