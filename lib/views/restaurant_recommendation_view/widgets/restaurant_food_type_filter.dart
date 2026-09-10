import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';

/// Single-select presentation filter for Quick Mode restaurant menus.
class RestaurantFoodTypeFilter extends StatelessWidget {
  const RestaurantFoodTypeFilter({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
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
        itemCount: options.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final String? value = index == 0 ? null : options[index - 1];
          return ChoiceChip(
            label: Text(value ?? 'All'),
            selected: selected == value,
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    ),
  );
}
