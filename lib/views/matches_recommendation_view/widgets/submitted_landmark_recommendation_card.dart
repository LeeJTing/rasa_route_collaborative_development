import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// Mobile-safe Matches-owned preview card for a real submitted landmark.
///
/// Mirrors [MatchesRestaurantCard]'s structure - photo + name + meta line,
/// the price/serves bar, one tag and the full-width action - so the
/// Submitted Landmarks tab reads like the Restaurants tab.
class SubmittedLandmarkRecommendationCard extends StatelessWidget {
  const SubmittedLandmarkRecommendationCard({
    super.key,
    required this.landmark,
    required this.onTap,
  });

  final SubmittedLandmarkRecommendation landmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? serves = landmark.foodNames.isEmpty
        ? null
        : 'Serves ${landmark.foodNames.join(', ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: onTap,
            borderRadius: AppRadius.cardRadius,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox.square(
                  dimension: AppSizes.restaurantCardImage,
                  child: AppImage(
                    source: landmark.imageUrl,
                    borderRadius: AppRadius.cardRadius,
                    semanticLabel: landmark.name,
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
                      if (landmark.category.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          landmark.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: <Widget>[
                          const Icon(
                            Icons.location_on_outlined,
                            size: AppSizes.iconSmall,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              _distanceLabel(landmark.distanceMetres),
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    landmark.price == null
                        ? 'Price unavailable'
                        : 'RM ${landmark.price!.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (serves != null)
                  Flexible(
                    child: Text(
                      serves,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Align(
            alignment: Alignment.centerLeft,
            child: AppTagChip(
              label: 'User Submitted Landmark',
              style: AppTagStyle.neutral,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('View Landmark Details'),
          ),
        ],
      ),
    );
  }

  String _distanceLabel(double distanceMetres) {
    if (!distanceMetres.isFinite) return 'Distance unavailable';
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}
