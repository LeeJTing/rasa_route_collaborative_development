import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/food_image_fallback.dart';

class RestaurantExpandedInfo extends StatelessWidget {
  const RestaurantExpandedInfo({
    super.key,
    required this.items,
    required this.onFoodImageTap,
  });

  final List<RestaurantItem> items;
  final ValueChanged<RestaurantItem> onFoodImageTap;

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
                    InkWell(
                      onTap: item.imageUrl?.trim().isNotEmpty == true
                          ? () => onFoodImageTap(item)
                          : null,
                      borderRadius: AppRadius.cardRadius,
                      child: SizedBox.square(
                        dimension: AppSizes.pairingImage,
                        child: AppImage(
                          source: item.imageUrl,
                          borderRadius: AppRadius.cardRadius,
                          semanticLabel: item.foodName,
                          fallback: const FoodImageFallback(),
                        ),
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
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              if (item.price != null) ...<Widget>[
                                const SizedBox(width: AppSpacing.sm),
                                Flexible(
                                  child: Text(
                                    '${item.currency} ${item.price!.toStringAsFixed(2)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(color: AppColors.accentRust),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (item.ingredients?.isNotEmpty == true) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            // The whole description, however long: no maxLines
                            // and no ellipsis, so nothing is cut in half.
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
