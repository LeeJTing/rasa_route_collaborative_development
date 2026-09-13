import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_item.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/food_image_fallback.dart';
import '../../common_widgets/place_menu_section.dart';

class RestaurantMenuPreview extends StatelessWidget {
  const RestaurantMenuPreview({
    super.key,
    required this.items,
    required this.onImageTap,
  });

  final List<RestaurantItem> items;
  final ValueChanged<RestaurantItem> onImageTap;

  @override
  Widget build(BuildContext context) => PlaceMenuSection(
    itemCount: items.length,
    emptyMessage: 'Menu information is not available yet.',
    children: <Widget>[
      for (final RestaurantItem item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              color: item.dietaryWarning == null
                  ? AppColors.surface
                  : AppColors.cardWarningBackground,
              border: Border.all(
                color: item.dietaryWarning == null
                    ? AppColors.cardBorder
                    : AppColors.cardWarningBorder,
              ),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    InkWell(
                      onTap: item.imageUrl?.trim().isNotEmpty == true
                          ? () => onImageTap(item)
                          : null,
                      borderRadius: AppRadius.cardRadius,
                      child: SizedBox.square(
                        dimension: AppSizes.menuItemImage,
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
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                              ),
                              if (item.price != null) ...<Widget>[
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${item.currency} '
                                  '${item.price!.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: AppColors.accentRust),
                                ),
                              ],
                            ],
                          ),
                          if (item.description?.trim().isNotEmpty ??
                              false) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              item.description!.trim(),
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
                  ],
                ),
                if (item.dietaryWarning != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: AppSizes.inlineNoticeIconSize,
                        color: AppColors.bannerWarningText,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          item.dietaryWarning!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.bannerWarningText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}
