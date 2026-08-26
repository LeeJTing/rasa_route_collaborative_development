import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';
import '../../../domain_model/local_food.dart';

class QuickSwitcherBar extends StatelessWidget {
  const QuickSwitcherBar({
    required this.foods,
    required this.replacementSide,
    required this.onSideChanged,
    required this.onFoodSelected,
    super.key,
  });

  final List<LocalFood> foods;
  final ComparisonSide replacementSide;
  final ValueChanged<ComparisonSide> onSideChanged;
  final ValueChanged<int> onFoodSelected;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.accentBrown,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Quick switch',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Choose the slot to replace, then tap another selected food.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<ComparisonSide>(
              segments: const <ButtonSegment<ComparisonSide>>[
                ButtonSegment<ComparisonSide>(
                  value: ComparisonSide.left,
                  label: Text(
                    'Replace left',
                    style: TextStyle(color: AppColors.accentBrown),
                  ),
                  icon: Icon(Icons.view_sidebar_rounded),
                ),
                ButtonSegment<ComparisonSide>(
                  value: ComparisonSide.right,
                  label: Text(
                    'Replace right',
                    style: TextStyle(color: AppColors.accentBrown),
                  ),
                  icon: Icon(Icons.vertical_split_rounded),
                ),
              ],
              selected: <ComparisonSide>{replacementSide},
              onSelectionChanged: (Set<ComparisonSide> value) {
                onSideChanged(value.first);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: foods.map((LocalFood food) {
                return ActionChip(
                  avatar: const Icon(Icons.add_circle_outline_rounded),
                  label: Text(food.name),
                  onPressed: () => onFoodSelected(food.id),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}
