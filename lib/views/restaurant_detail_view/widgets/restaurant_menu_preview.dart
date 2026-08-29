import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';

class RestaurantMenuPreview extends StatelessWidget {
  const RestaurantMenuPreview({super.key, required this.items});

  final List<RestaurantItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Local Foods Served',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        const SizedBox(height: AppSpacing.md),
        if (items.isEmpty)
          Text(
            'Menu information is not available yet.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
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
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.accentRust,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
