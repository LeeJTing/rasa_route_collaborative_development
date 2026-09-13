import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// Single-select presentation filter for Quick Mode restaurant menus.
///
/// There is no "All" option - one type is always selected (Quick Mode
/// defaults to 'Food'), and picking a chip re-runs the nearby search for
/// that type rather than filtering the restaurants already on screen.
class RestaurantFoodTypeFilter extends StatelessWidget {
  const RestaurantFoodTypeFilter({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: SizedBox(
        height: AppSizes.minTapTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, _) =>
          const SizedBox(width: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) {
            final String value = options[index];
            final bool isSelected = selected == value;

            return ChoiceChip(
              label: Text(value),
              selected: isSelected,
              onSelected: (_) => onSelected(value),

              // Keep the normal unselected chip background from the theme.
              selectedColor: AppColors.primary,

              labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? AppColors.onPrimary
                    : AppColors.textPrimary,
                fontWeight: isSelected
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),

              checkmarkColor: AppColors.onPrimary,

              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.outline,
              ),
            );
          },
        ),
      ),
    );
  }
}