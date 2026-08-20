import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';
import 'restaurant_expanded_info.dart';

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.expanded,
    required this.onExpand,
  });

  final Restaurant restaurant;
  final bool expanded;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onExpand,
        child: Column(
          children: <Widget>[
            Padding(
              padding: AppSpacing.cardPadding,
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
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: <Widget>[
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '${restaurant.rating?.toStringAsFixed(1) ?? '—'} (${restaurant.reviewCount ?? 0})',
                            ),
                            const SizedBox(width: AppSpacing.md),
                            const Icon(Icons.location_on_outlined, size: 16),
                            Text(restaurant.distanceLabel),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: <Widget>[
                            AppTagChip(
                              label: restaurant.category,
                              style: AppTagStyle.category,
                            ),
                            if (restaurant.isHalal == true)
                              const AppTagChip(
                                label: 'Halal',
                                style: AppTagStyle.halal,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (expanded) RestaurantExpandedInfo(items: restaurant.items),
          ],
        ),
      ),
    );
  }
}
