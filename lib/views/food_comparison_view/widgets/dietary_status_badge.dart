import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';

class DietaryStatusBadge extends StatelessWidget {
  const DietaryStatusBadge({required this.assessment, super.key});

  final DietaryAssessment assessment;

  @override
  Widget build(BuildContext context) {
    // Suitable = info-banner green (#9EFFB3 at 70% bg, #1F7300 text);
    // allergy match = warning banner (#FFA9A9 at 70% bg, #921616 text).
    final Color background = assessment.isSuitable
        ? AppColors.bannerInfoBackground
        : AppColors.bannerWarningBackground;
    final Color foreground = assessment.isSuitable
        ? AppColors.bannerInfoText
        : AppColors.bannerWarningText;

    return Semantics(
      label: assessment.message,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadius.sm),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              assessment.isSuitable
                  ? Icons.verified_rounded
                  : Icons.warning_rounded,
              size: AppSizes.iconSmall,
              color: foreground,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                assessment.message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
