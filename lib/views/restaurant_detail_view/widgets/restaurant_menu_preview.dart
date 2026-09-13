import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/food_image_fallback.dart';

class RestaurantMenuPreview extends StatelessWidget {
  const RestaurantMenuPreview({super.key, required this.items});

  final List<RestaurantItem> items;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Local Foods Served (${items.length})',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        children: <Widget>[
          if (items.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Menu information is not available yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...items.map(
              (RestaurantItem item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.cardBorder),
                    borderRadius: AppRadius.cardRadius,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(
                        dimension: AppSizes.pairingImage,
                        child: AppImage(
                          source: item.imageUrl,
                          borderRadius: AppRadius.cardRadius,
                          semanticLabel: item.foodName,
                          fallback: const FoodImageFallback(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              item.foodName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (item.description?.trim().isNotEmpty ??
                                false) ...<Widget>[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                item.description!.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                            Text(
                              item.foodCategory,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (item.price != null)
                        Text(
                          '${item.currency} ${item.price!.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: AppColors.accentRust),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
