import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_pairing.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

class FoodPairingList extends StatelessWidget {
  const FoodPairingList({super.key, required this.pairings});

  final List<FoodPairing> pairings;

  String _imageFor(FoodPairing pairing) => switch (pairing.pairedFoodName) {
    'Teh Tarik' => 'assets/images/figma/restaurant_04.png',
    'Cendol' => 'assets/images/figma/detail_06.png',
    'Bubur Cha Cha' => 'assets/images/figma/detail_07.png',
    _ => 'assets/images/figma/detail_11.png',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: pairings.map((FoodPairing pairing) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(
                dimension: AppSizes.pairingImage,
                child: AppImage(
                  source: _imageFor(pairing),
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
                  ],
                ),
              ),
              AppTagChip(
                label: '${(pairing.score * 100).round()}% match',
                style: AppTagStyle.match,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
