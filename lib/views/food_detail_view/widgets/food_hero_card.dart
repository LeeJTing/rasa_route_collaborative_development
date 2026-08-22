import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';

class FoodHeroCard extends StatelessWidget {
  const FoodHeroCard({
    super.key,
    required this.food,
    required this.isLiked,
    required this.onLike,
    required this.onImageTap,
  });

  final LocalFood food;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onImageTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Enlarge ${food.name} image',
          child: InkWell(
            onTap: onImageTap,
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
            child: SizedBox.square(
              dimension: AppSizes.foodHeroImage,
              child: AppImage(
                source: food.imageUrl,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadius.lg),
                ),
                semanticLabel: food.name,
              ),
            ),
          ),
        ),
        Positioned(
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: isLiked ? 'Remove from favourites' : 'Add to favourites',
              onPressed: onLike,
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? AppColors.error : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
