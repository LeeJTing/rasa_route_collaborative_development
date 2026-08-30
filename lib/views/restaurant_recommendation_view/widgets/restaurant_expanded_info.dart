import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';

class RestaurantExpandedInfo extends StatelessWidget {
  const RestaurantExpandedInfo({super.key, required this.items});

  final List<RestaurantItem> items;

  static const int _previewItemLimit = 4;

  @override
  Widget build(BuildContext context) {
    final List<RestaurantItem> previewItems = items
        .take(_previewItemLimit)
        .toList(growable: false);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.insetSurface,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (items.isEmpty)
            Text(
              'Menu details are not available yet.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ...previewItems.map(
              (RestaurantItem item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: AppSizes.pairingImage,
                      child: AppImage(
                        source: item.imageUrl,
                        borderRadius: AppRadius.cardRadius,
                        semanticLabel: item.foodName,
                        fallback: const _FoodImageFallback(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  item.foodName,
                                  style: Theme.of(context).textTheme.titleSmall,
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
                          if (item.ingredients?.isNotEmpty == true) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              item.ingredients!,
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
          if (items.length > _previewItemLimit)
            Center(
              child: Text(
                'Showing $_previewItemLimit of ${items.length} local foods · '
                'Tap the restaurant for all',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class _FoodImageFallback extends StatelessWidget {
  const _FoodImageFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceVariant,
    child: Center(
      child: Icon(Icons.ramen_dining, color: AppColors.textSecondary),
    ),
  );
}
