import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/matches_recommendation.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// Mobile-safe Matches-owned preview card for a real submitted landmark.
///
/// Mirrors [MatchesRestaurantCard]'s structure field for field - photo,
/// name, address, one metric row carrying the distance and the category
/// chip, the "From RM x" / "Serves ..." bar, one tag and the full-width
/// action - so the Submitted Landmarks tab reads like the Restaurants tab.
/// The one field a landmark cannot carry is the rating star: submitted
/// landmarks are never rated, so the metric row starts at the distance.
/// The PHOTO keeps its own tap (like the quick-mode landmark card): it opens
/// full-screen with the "User submitted photo" note.
class SubmittedLandmarkRecommendationCard extends StatelessWidget {
  const SubmittedLandmarkRecommendationCard({
    super.key,
    required this.landmark,
    required this.onTap,
    required this.onImageTap,
  });

  final SubmittedLandmarkRecommendation landmark;
  final VoidCallback onTap;

  /// Opens the landmark's photo full-screen - the dark scrim with the
  /// "User submitted photo" note, exactly like the quick-mode card.
  final VoidCallback onImageTap;

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
                // The photo keeps its OWN tap - it opens full-screen with the
                // "User submitted photo" note, exactly like the quick-mode
                // landmark card; the card-wide tap covers everything else.
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        landmark.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (landmark.address.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          landmark.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _IconLabel(
                            icon: Icons.location_on_outlined,
                            label: _distanceLabel(landmark.distanceMetres),
                          ),
                          AppTagChip(
                            label: landmark.categoryLabel,
                            style: AppTagStyle.category,
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
                        : 'From RM ${landmark.price!.toStringAsFixed(2)}',
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

/// The same icon + label pair `MatchesRestaurantCard` uses for its metric
/// row, so both tabs show their metrics identically.
class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: AppSizes.iconSmall, color: AppColors.textPrimary),
      const SizedBox(width: AppSpacing.xs),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
