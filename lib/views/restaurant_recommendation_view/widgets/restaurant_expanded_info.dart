import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';

class RestaurantExpandedInfo extends StatelessWidget {
  const RestaurantExpandedInfo({super.key, required this.items});

  final List<RestaurantItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.insetSurface,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Popular local food',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            Text(
              'Menu details are not available yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...items.map(
              (RestaurantItem item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                      child: Text(
                        item.foodName,
                        style: Theme.of(context).textTheme.bodyMedium,
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
        ],
      ),
    );
  }
}
