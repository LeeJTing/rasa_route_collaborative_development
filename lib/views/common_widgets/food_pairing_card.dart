import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../domain_model/food_pairing.dart';
import '../../domain_model/local_food.dart';
import 'app_image.dart';
import 'app_tag_chip.dart';

class FoodPairingCard extends StatelessWidget {
  const FoodPairingCard({
    super.key,
    required this.pairing,
    required this.onTap,
    this.pairedFood,
  });

  final FoodPairing pairing;
  final LocalFood? pairedFood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(
                dimension: AppSizes.pairingImage,
                child: AppImage(
                  source: pairedFood == null || pairedFood!.imageUrls.isEmpty
                      ? null
                      : pairedFood!.imageUrls.first,
                  borderRadius: AppRadius.cardRadius,
                  semanticLabel: pairing.pairedFoodName,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      pairing.pairedFoodName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.accentRust,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      pairing.reason,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (pairing.dietaryStatus ==
                        FoodPairingDietaryStatus.warning) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '⚠ ${pairing.warning ?? 'Verify with the seller before ordering.'}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppTagChip(
                label: '${pairing.matchPercentage}% match',
                style: AppTagStyle.match,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
