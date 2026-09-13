import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/food_image_fallback.dart';
import 'place_metric.dart';

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
          // Same header shape as `RestaurantCard` - photo, name, one metric
          // row, category - so the two Quick Mode lists read as one design.
          // The ONLY difference is the rating: a submitted landmark has none,
          // so NO empty slot is kept for one - the distance takes the metric
          // row on its own, right under the name (user request, 2026-09-14:
          // the reserved half read as a gap above the category).
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // The photo keeps its OWN tap (the tourist's capture opens
                  // enlarged right here - a restaurant card's photo has no
                  // such action); the card-wide tap covers everything else.
                  InkWell(
                    onTap: landmark.imageUrl?.trim().isNotEmpty == true
                        ? () => onImageTap(landmark.imageUrl, landmark.name)
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
                        // No rating for a submitted landmark, so no empty
                        // half-line is reserved for one (user request,
                        // 2026-09-14) - the distance takes the metric row
                        // on its own, right under the name.
                        PlaceMetric(
                          icon: Icons.location_on_outlined,
                          label: _distanceLabel(landmark.distanceMetres),
                        ),
                        if (landmark.categoryLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            landmark.categoryLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
                      (SubmittedLandmarkDish dish) =>
                          _LandmarkDishRow(dish: dish, onImageTap: onImageTap),
                    ),
                  if (landmark.dishes.length > _previewLimit)
                    Center(
                      child: Text(
                        'Showing $_previewLimit of '
                        '${landmark.dishes.length} local foods · '
                        'Tap the landmark for all',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
  const _LandmarkDishRow({required this.dish, required this.onImageTap});

  final SubmittedLandmarkDish dish;
  final void Function(String? source, String semanticLabel) onImageTap;

  /// The row's grey line: the dish's DESCRIPTION, exactly like a restaurant
  /// menu row shows its own - the recorded ingredients are only the fallback
  /// when the dish carries no description (user request, 2026-09-14: the
  /// ingredients list was showing where the restaurant shows a description).
  String? get _displayText {
    final String description = dish.description?.trim() ?? '';
    if (description.isNotEmpty) return description;
    final String ingredients = dish.ingredients?.trim() ?? '';
    return ingredients.isEmpty ? null : ingredients;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          InkWell(
            onTap: dish.imageUrl?.trim().isNotEmpty == true
                ? () => onImageTap(dish.imageUrl, dish.name)
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
                LayoutBuilder(
                  builder:
                      (BuildContext context, BoxConstraints constraints) =>
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  dish.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                              ),
                              if (dish.price != null) ...<Widget>[
                                const SizedBox(width: AppSpacing.sm),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        constraints.maxWidth *
                                        AppLayoutRatios
                                            .restaurantMenuPriceMaxWidthFraction,
                                  ),
                                  child: Text(
                                    'RM ${dish.price!.toStringAsFixed(2)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: AppColors.accentRust),
                                  ),
                                ),
                              ],
                            ],
                          ),
                ),
                if (_displayText != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  // The whole text, however long, exactly like a restaurant
                  // menu row: no maxLines and no ellipsis, so nothing is cut
                  // in half.
                  Text(
                    _displayText!,
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
