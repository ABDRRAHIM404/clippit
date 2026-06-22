import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/clip_suggestion.dart';

class ClipCard extends StatelessWidget {
  final ClipSuggestion clip;
  final int index;
  final VoidCallback onTap;

  const ClipCard({
    super.key,
    required this.clip,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double duration = clip.endTimeSeconds - clip.startTimeSeconds;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Visual Header / Thumbnail Box
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
                        Icons.movie_outlined,
                        size: 40,
                        color: AppColors.textMuted.withOpacity(0.5),
                      ),
                    ),
                  ),
                  
                  // Duration Label (Bottom Right)
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

                  // Glowing Fire Indicator (Top Right)
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

                  // Highlight Moment Tag (Top Left)
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
