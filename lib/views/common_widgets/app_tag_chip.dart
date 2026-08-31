import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

// ===========================================================================
// Tourist profile (ChinShunYon) - added `dietary` for dietary-restriction
// chips on the Profile / edit screens.
// ===========================================================================
enum AppTagStyle { meal, category, taste, neutral, match, dietary }
// End of Tourist profile (ChinShunYon) -------------------------------------

/// Compact colour-coded metadata pill shared by food and restaurant screens.
class AppTagChip extends StatelessWidget {
  const AppTagChip({
    super.key,
    required this.label,
    this.style = AppTagStyle.neutral,
  });

  final String label;
  final AppTagStyle style;

  @override
  Widget build(BuildContext context) {
    final (Color, Color, Color) colors = switch (style) {
      AppTagStyle.meal => (
        AppColors.tagMealTypeBackground,
        AppColors.tagMealTypeBorder,
        AppColors.tagMealTypeText,
      ),
      AppTagStyle.category || AppTagStyle.match => (
        AppColors.tagCategoryBackground,
        AppColors.tagCategoryBorder,
        AppColors.tagCategoryText,
      ),
      AppTagStyle.taste => (
        AppColors.tagTasteBackground,
        AppColors.tagTasteBorder,
        AppColors.tagTasteText,
      ),
      // Tourist profile (ChinShunYon): dietary-restriction chips.
      AppTagStyle.dietary => (
        AppColors.tagDietaryBackground,
        AppColors.tagDietaryBorder,
        AppColors.tagDietaryText,
      ),
      // End of Tourist profile (ChinShunYon).
      AppTagStyle.neutral => (
        AppColors.tagNeutralBackground,
        AppColors.tagNeutralBorder,
        AppColors.tagNeutralText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        border: Border.all(color: colors.$2),
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.$3),
      ),
    );
  }
}
