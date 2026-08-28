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
      // The card stays white when selected - selection is shown with a
      // primary border and a stronger shadow instead of tinting the surface.
      color: AppColors.surface,
      elevation: isSelected
          ? AppSizes.selectedCardElevation
          : AppSizes.cardElevation,
      shadowColor: AppColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.cardBorder,
          width: isSelected ? AppSizes.borderWidth * 2 : AppSizes.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox.square(
                dimension: AppSizes.foodCardImage,
                child: AppImage(
                  source: food.imageUrls.isEmpty ? null : food.imageUrls.first,
                  semanticLabel: food.name,
                  borderRadius: AppRadius.cardRadius,
                  fallback: const _FoodImageUnavailable(),
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

class _FoodImageUnavailable extends StatelessWidget {
  const _FoodImageUnavailable();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Image unavailable',
    image: true,
    child: ColoredBox(
      color: AppColors.surfaceVariant,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.restaurant_menu, color: AppColors.accentBrown),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'No image',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.accentBrownMuted),
          ),
        ],
      ),
    ),
  );
}
