import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Neutral replacement for a missing or unreachable restaurant-item photo.
class FoodImageFallback extends StatelessWidget {
  const FoodImageFallback({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surfaceVariant,
    child: Semantics(
      image: true,
      label: 'Food photo unavailable',
      child: const Center(
        child: Icon(Icons.no_food_outlined, color: AppColors.textSecondary),
      ),
    ),
  );
}
