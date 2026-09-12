import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/food_image_fallback.dart';

class SubmittedLandmarkCard extends StatelessWidget {
  const SubmittedLandmarkCard({
    super.key,
    required this.landmark,
    required this.expanded,
    required this.onExpand,
    required this.onTap,
    required this.onImageTap,
  });

  final SubmittedLandmarkRecommendation landmark;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onTap;

  /// Opens either the landmark image or an individual dish image.
  final void Function(String? source, String semanticLabel) onImageTap;

  static const int _previewLimit = 4;

  @override
  Widget build(BuildContext context) {
    final List<SubmittedLandmarkDish> preview = landmark.dishes
        .take(_previewLimit)
        .toList(growable: false);

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: AppSpacing.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                InkWell(
                  onTap: landmark.imageUrl?.trim().isNotEmpty == true
                      ? () => onImageTap(
                    landmark.imageUrl,
                    landmark.name,
                  )
                      : null,
                  borderRadius: AppRadius.cardRadius,
                  child: SizedBox.square(
                    dimension: AppSizes.restaurantCardImage,
                    child: AppImage(
                      source: landmark.imageUrl,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: landmark.name,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: AppRadius.cardRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            landmark.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.location_on_outlined,
                                size: AppSizes.iconCompact,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  _distanceLabel(landmark.distanceMetres),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (landmark.category.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              landmark.category,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
              ),
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.insetSurface,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (preview.isEmpty)
                    Text(
                      'Food details are not available yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...preview.map(
                          (SubmittedLandmarkDish dish) => _LandmarkDishRow(
                        dish: dish,
                        onImageTap: onImageTap,
                      ),
                    ),
                  if (landmark.dishes.length > _previewLimit)
                    Center(
                      child: Text(
                        'Showing $_previewLimit of '
                            '${landmark.dishes.length} local foods · '
                            'Tap the landmark for all',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Center(
            child: IconButton(
              tooltip: expanded ? 'Hide local food' : 'Show local food',
              onPressed: onExpand,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _distanceLabel(double metres) {
    if (metres < 1000) {
      return '${metres.round()} m';
    }

    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}

class _LandmarkDishRow extends StatelessWidget {
  const _LandmarkDishRow({
    required this.dish,
    required this.onImageTap,
  });

  final SubmittedLandmarkDish dish;
  final void Function(String? source, String semanticLabel) onImageTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          InkWell(
            onTap: dish.imageUrl?.trim().isNotEmpty == true
                ? () => onImageTap(
              dish.imageUrl,
              dish.name,
            )
                : null,
            borderRadius: AppRadius.cardRadius,
            child: SizedBox.square(
              dimension: AppSizes.pairingImage,
              child: AppImage(
                source: dish.imageUrl,
                borderRadius: AppRadius.cardRadius,
                semanticLabel: dish.name,
                fallback: const FoodImageFallback(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        dish.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (dish.price != null)
                      Flexible(
                        child: Text(
                          'RM ${dish.price!.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                            color: AppColors.accentRust,
                          ),
                        ),
                      ),
                  ],
                ),
                if (dish.ingredients?.trim().isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    dish.ingredients!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}