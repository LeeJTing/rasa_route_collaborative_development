import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

class ComparisonNotice extends StatelessWidget {
  const ComparisonNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Price estimate warning',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.bannerCautionBackground,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.front_hand_rounded,
              // #575700 at 100% opacity.
              color: AppColors.bannerCautionText,
              size: AppSizes.iconMedium,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Prices are estimates from listed restaurants. Tourist prices can vary by location, portion, season and dining setting.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.bannerCautionText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
