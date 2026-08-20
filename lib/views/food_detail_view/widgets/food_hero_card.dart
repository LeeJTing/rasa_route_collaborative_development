import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

class FoodHeroCard extends StatelessWidget {
  const FoodHeroCard({
    super.key,
    required this.food,
    required this.isLiked,
    required this.onLike,
  });

  final LocalFood food;
  final bool isLiked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            SizedBox.square(
              dimension: AppSizes.foodHeroImage,
              child: AppImage(
                source: food.imageUrl,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.lg),
                ),
                semanticLabel: food.name,
              ),
            ),
            Positioned(
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: Material(
                color: AppColors.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: isLiked
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  onPressed: onLike,
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            AppTagChip(label: food.mealType, style: AppTagStyle.meal),
            AppTagChip(label: food.category, style: AppTagStyle.category),
            AppTagChip(label: food.cookingStyle, style: AppTagStyle.taste),
          ],
        ),
      ],
    );
  }
}
