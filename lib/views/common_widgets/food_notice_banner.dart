import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

enum FoodNoticeType { allergy, caution, degraded, provided }

class FoodNoticeBanner extends StatelessWidget {
  const FoodNoticeBanner({
    super.key,
    required this.message,
    required this.type,
    this.onTap,
  });

  final String message;
  final FoodNoticeType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground, IconData icon) = switch (type) {
      // Severe warning (e.g. an allergy to confirm with the seller).
      FoodNoticeType.allergy => (
        AppColors.bannerWarningBackground,
        AppColors.bannerWarningText,
        Icons.warning_amber_rounded,
      ),
      // Gentle notice (e.g. a possible name collision).
      FoodNoticeType.caution => (
        AppColors.bannerCautionBackground,
        AppColors.bannerCautionText,
        Icons.info_outline,
      ),
      // The AI service rotated to an env-configured fallback - caution only.
      FoodNoticeType.degraded => (
        AppColors.bannerCautionBackground,
        AppColors.bannerCautionText,
        Icons.warning_amber_rounded,
      ),
      // Positive confirmation (e.g. the photo really came from the restaurant
      // itself). Green, the same banner family the app already uses.
      FoodNoticeType.provided => (
        AppColors.bannerInfoBackground,
        AppColors.bannerInfoText,
        Icons.verified_outlined,
      ),
    };
    return Material(
      color: background,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            children: <Widget>[
              Icon(icon, color: foreground),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
