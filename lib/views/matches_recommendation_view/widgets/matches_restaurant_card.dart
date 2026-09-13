import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

/// Mobile-safe restaurant recommendation inside one liked-food container.
class MatchesRestaurantCard extends StatelessWidget {
  const MatchesRestaurantCard({
    super.key,
    required this.restaurant,
    required this.matchedFoodName,
    required this.onTap,
  });

  final Restaurant restaurant;
  final String matchedFoodName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double? minimumPrice = _minimumPrice;
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
                    source: restaurant.imageUrl,
                    borderRadius: AppRadius.cardRadius,
                    semanticLabel: restaurant.name,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        restaurant.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        restaurant.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _IconLabel(
                            icon: Icons.star,
                            iconColor: AppColors.secondary,
                            label: restaurant.rating == null
                                ? 'New'
                                : restaurant.rating!.toStringAsFixed(1),
                          ),
                          _IconLabel(
                            icon: Icons.location_on_outlined,
                            label: _distanceLabel(restaurant.distanceMetres),
                          ),
                          if (restaurant.category.isNotEmpty)
                            AppTagChip(
                              label: restaurant.category,
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
                    minimumPrice == null
                        ? 'Price unavailable'
                        : 'From RM ${minimumPrice.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Flexible(
                  child: Text(
                    'Serves $matchedFoodName',
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
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.restaurant_outlined),
            label: const Text('View Restaurant'),
          ),
        ],
      ),
    );
  }

  double? get _minimumPrice {
    final List<double> prices = restaurant.items
        .map((RestaurantItem item) => item.price)
        .whereType<double>()
        .toList(growable: false);
    if (prices.isEmpty) return null;
    prices.sort();
    return prices.first;
  }

  String _distanceLabel(double? distanceMetres) {
    if (distanceMetres == null) return 'Distance unavailable';
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({
    required this.icon,
    required this.label,
    this.iconColor = AppColors.textPrimary,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: AppSizes.iconSmall, color: iconColor),
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
