import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';
import 'restaurant_expanded_info.dart';

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.distanceLabel,
    required this.expanded,
    required this.onExpand,
    required this.onTap,
    required this.onFoodImageTap,
  });

  final Restaurant restaurant;
  final String distanceLabel;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onTap;
  final ValueChanged<RestaurantItem> onFoodImageTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _RestaurantMetric(
                                icon: Icons.star,
                                iconColor: AppColors.secondary,
                                label: restaurant.reviewCount == null
                                    ? restaurant.rating?.toStringAsFixed(1) ??
                                          '—'
                                    : '${restaurant.rating?.toStringAsFixed(1) ?? '—'} (${restaurant.reviewCount})',
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _RestaurantMetric(
                                icon: Icons.location_on_outlined,
                                label: distanceLabel,
                              ),
                            ),
                          ],
                        ),
                        if (restaurant.category.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            restaurant.category,
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
            RestaurantExpandedInfo(
              items: restaurant.items,
              onFoodImageTap: onFoodImageTap,
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
}

class _RestaurantMetric extends StatelessWidget {
  const _RestaurantMetric({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: AppSizes.iconCompact, color: iconColor),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}
