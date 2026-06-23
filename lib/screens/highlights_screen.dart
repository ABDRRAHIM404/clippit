import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/clip_suggestion.dart';
import '../widgets/clip_card.dart';

class HighlightsScreen extends StatelessWidget {
  final List<ClipSuggestion> suggestions;
  final String sourceTitle;
  final Function(ClipSuggestion selectedClip) onClipSelected;
  final VoidCallback onBackPressed; // 🌟 Added callback to handle returning to dashboard

  const HighlightsScreen({
    super.key,
    required this.suggestions,
    required this.sourceTitle,
    required this.onClipSelected,
    required this.onBackPressed,
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
          onPressed: onBackPressed, // 🌟 Triggers the reset callback to return safely to HomeScreen
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
                      return ClipCard(
                        clip: clip,
                        index: index,
                        onTap: () => onClipSelected(clip),
                      );
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
}
