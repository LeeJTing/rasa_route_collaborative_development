import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';

class FoodHeroCard extends StatefulWidget {
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
  final ValueChanged<int> onImageTap;

  @override
  State<FoodHeroCard> createState() => _FoodHeroCardState();
}

class _FoodHeroCardState extends State<FoodHeroCard> {
  int _currentImage = 0;

  @override
  Widget build(BuildContext context) {
    final List<String?> images = widget.food.imageUrls.isEmpty
        ? <String?>[null]
        : widget.food.imageUrls;
    return Stack(
      children: <Widget>[
        Semantics(
          button: true,
          label: 'Enlarge ${widget.food.name} image',
          child: InkWell(
            onTap: () => widget.onImageTap(_currentImage),
            borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
            child: SizedBox(
              width: AppSizes.foodHeroImage,
              height: AppSizes.foodHeroImage,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  PageView.builder(
                    itemCount: images.length,
                    onPageChanged: (int index) =>
                        setState(() => _currentImage = index),
                    itemBuilder: (BuildContext context, int index) => AppImage(
                      source: images[index],
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadius.lg),
                      ),
                      semanticLabel:
                          '${widget.food.name} image ${index + 1} of ${images.length}',
                    ),
                  ),
                  if (images.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List<Widget>.generate(
                          images.length,
                          (int index) => Container(
                            width: AppSpacing.sm,
                            height: AppSpacing.sm,
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: index == _currentImage
                                  ? AppColors.primary
                                  : AppColors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
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
              tooltip: widget.isLiked
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              onPressed: widget.onLike,
              icon: Icon(
                widget.isLiked ? Icons.favorite : Icons.favorite_border,
                color: widget.isLiked
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
