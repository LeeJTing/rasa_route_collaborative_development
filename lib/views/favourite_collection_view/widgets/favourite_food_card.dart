import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// One saved dish in the Favourite Food Collection - image, name, meal /
/// category / taste tags and a short description, exactly like the mock-up's
/// favourite cards.
class FavouriteFoodCard extends StatelessWidget {
  const FavouriteFoodCard({super.key, required this.food, required this.onTap});

  final LocalFood food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: AppSizes.cardElevation,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorderWarm),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(
                dimension: AppSizes.foodCardImage,
                child: AppImage(
                  source: food.imageUrl,
                  semanticLabel: food.name,
                  borderRadius: AppRadius.cardRadius,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      food.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        if (food.mealType.isNotEmpty)
                          AppTagChip(
                            label: food.mealType,
                            style: AppTagStyle.meal,
                          ),
                        if (food.category.isNotEmpty)
                          AppTagChip(
                            label: food.category,
                            style: AppTagStyle.category,
                          ),
                        if (food.mainTaste.isNotEmpty)
                          AppTagChip(
                            label: food.mainTaste,
                            style: AppTagStyle.taste,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      food.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
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
}
