import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// Mobile-safe Matches-owned preview card for a real submitted landmark.
class SubmittedLandmarkRecommendationCard extends StatelessWidget {
  const SubmittedLandmarkRecommendationCard({
    super.key,
    required this.landmark,
    required this.onTap,
  });

  final SubmittedLandmarkRecommendation landmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
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
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      landmark.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: <Widget>[
                        const Icon(
                          Icons.location_on_outlined,
                          size: AppSizes.iconSmall,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          _distanceLabel(landmark.distanceMetres),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    if (landmark.price != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'RM ${landmark.price!.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.accentRust,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            const AppTagChip(
              label: 'User Submitted Landmark',
              style: AppTagStyle.neutral,
            ),
            ...landmark.foodNames.map(
              (String foodName) =>
                  AppTagChip(label: foodName, style: AppTagStyle.match),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.info_outline),
          label: const Text('View Landmark Details'),
        ),
      ],
    ),
  );

  String _distanceLabel(double distanceMetres) {
    if (!distanceMetres.isFinite) return 'Distance unavailable';
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}
