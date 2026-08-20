import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

class LocalFoodCard extends StatelessWidget {
  const LocalFoodCard({
    super.key,
    required this.food,
    required this.isSelecting,
    required this.isSelected,
    required this.onTap,
    required this.onFavourite,
  });

  final LocalFood food;
  final bool isSelecting;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.primaryContainer : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: <Widget>[
                        AppTagChip(
                          label: food.mealType,
                          style: AppTagStyle.meal,
                        ),
                        AppTagChip(
                          label: food.category,
                          style: AppTagStyle.category,
                        ),
                        AppTagChip(
                          label: food.cookingStyle,
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
              IconButton(
                tooltip: isSelecting
                    ? 'Select ${food.name}'
                    : 'Favourite ${food.name}',
                onPressed: isSelecting ? onTap : onFavourite,
                icon: Icon(
                  isSelecting
                      ? (isSelected
                            ? Icons.check_circle
                            : Icons.circle_outlined)
                      : (food.isFavourite
                            ? Icons.favorite
                            : Icons.favorite_border),
                  color: isSelecting
                      ? AppColors.primary
                      : (food.isFavourite
                            ? AppColors.error
                            : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
