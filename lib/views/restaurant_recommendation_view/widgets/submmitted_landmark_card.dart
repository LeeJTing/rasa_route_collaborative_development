import 'package:flutter/material.dart';

import '/../app/theme/app_colors.dart';
import '/../app/theme/app_dimensions.dart';
import '/../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';

class SubmittedLandmarkCard extends StatelessWidget {
  const SubmittedLandmarkCard({
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
  final VoidCallback onImageTap;

  static const int _previewLimit = 4;

  @override
  Widget build(BuildContext context) {
    final List<String> preview = landmark.foodNames
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
                      ? onImageTap
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
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (landmark.category.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              landmark.category,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.location_on_outlined,
                                size: AppSizes.iconCompact,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(_distanceLabel(landmark.distanceMetres)),
                            ],
                          ),
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
                          (String foodName) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          foodName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  if (landmark.foodNames.length > _previewLimit)
                    Center(
                      child: Text(
                        'Showing $_previewLimit of ${landmark.foodNames.length} local foods · Tap the landmark for all',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          IconButton(
            tooltip: expanded ? 'Hide local food' : 'Show local food',
            onPressed: onExpand,
            icon: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
          ),
        ],
      ),
    );
  }

  static String _distanceLabel(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}
