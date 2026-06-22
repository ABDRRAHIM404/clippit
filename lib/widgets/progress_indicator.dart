import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GlowingProgressIndicator extends StatelessWidget {
  final String statusMessage;
  final double progress;

  const GlowingProgressIndicator({
    super.key,
    required this.statusMessage,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer glowing layer
            Container(
              height: 140,
              width: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryLight.withOpacity(0.15),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            
            // Progress Track Spinner
            SizedBox(
              height: 120,
              width: 120,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 6,
                backgroundColor: AppColors.surfaceLight,
                color: AppColors.accentNeon,
              ),
            ),
            
            // Dynamic text indicator
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    fontFamily: 'Montserrat',
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'PROCESSED',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 36),
        Text(
          statusMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
