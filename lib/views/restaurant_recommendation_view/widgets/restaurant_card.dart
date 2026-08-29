import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
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
  });

  final Restaurant restaurant;
  final String distanceLabel;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onTap;

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
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.star,
                              size: AppSizes.iconCompact,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              restaurant.reviewCount == null
                                  ? restaurant.rating?.toStringAsFixed(1) ?? '—'
                                  : '${restaurant.rating?.toStringAsFixed(1) ?? '—'} (${restaurant.reviewCount})',
                            ),
                            const SizedBox(width: AppSpacing.md),
                            const Icon(
                              Icons.location_on_outlined,
                              size: AppSizes.iconCompact,
                            ),
                            Text(distanceLabel),
                          ],
                        ),
                        if (restaurant.category.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            restaurant.category,
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
          if (expanded) RestaurantExpandedInfo(items: restaurant.items),
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
