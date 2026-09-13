import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';
import 'food_notice_banner.dart';

/// Figma's Food Detail name-collision section: the alternate dish is shown as
/// a real food card, followed by the ordering caution.
class FoodNameCollisionCard extends StatelessWidget {
  const FoodNameCollisionCard({
    super.key,
    required this.currentFoodName,
    required this.alternateFood,
    required this.onTap,
  });

  final String currentFoodName;
  final LocalFood alternateFood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LocalFood alternate = alternateFood;
    final String taste = alternate.mainTaste.isNotEmpty
        ? alternate.mainTaste
        : alternate.tastes.isEmpty
        ? ''
        : alternate.tastes.first;
    return Column(
      children: <Widget>[
        Material(
          color: AppColors.background,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.cardBorder),
            borderRadius: AppRadius.cardRadius,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.cardRadius,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox.square(
                    dimension: AppSizes.recommendationImage,
                    child: AppImage(
                      source: alternate.imageUrl,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: alternate.name,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          alternate.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            if (alternate.mealType.isNotEmpty)
                              AppTagChip(
                                label: alternate.mealType,
                                style: AppTagStyle.meal,
                              ),
                            if (alternate.category.isNotEmpty)
                              AppTagChip(
                                label: alternate.category,
                                style: AppTagStyle.category,
                              ),
                            if (taste.isNotEmpty)
                              AppTagChip(
                                label: taste,
                                style: AppTagStyle.taste,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          alternate.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.accentBrownMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FoodNoticeBanner(
          message:
              'Ordering "$currentFoodName" may refer to '
              '"${alternate.name}" in some restaurants. Please double-check '
              'with the seller before placing your order.',
          type: FoodNoticeType.caution,
        ),
      ],
    );
  }
}
