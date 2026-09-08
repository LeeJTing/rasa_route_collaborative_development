import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';
import '../../../domain_model/local_food.dart';

class QuickSwitcherBar extends StatefulWidget {
  const QuickSwitcherBar({
    required this.foods,
    required this.replacementSide,
    required this.leftSlotName,
    required this.rightSlotName,
    required this.onSideChanged,
    required this.onFoodSelected,
    super.key,
  });

  final List<LocalFood> foods;
  final ComparisonSide replacementSide;

  /// The dish currently sitting in each slot, so the user can see what a
  /// swap will replace.
  final String leftSlotName;
  final String rightSlotName;
  final ValueChanged<ComparisonSide> onSideChanged;
  final ValueChanged<int> onFoodSelected;

  @override
  State<QuickSwitcherBar> createState() => _QuickSwitcherBarState();
}

class _QuickSwitcherBarState extends State<QuickSwitcherBar> {
  /// The last candidate food tapped - shown in the system orange so the user
  /// sees which one is being placed, even when many foods are listed.
  int? _highlightedFoodId;

  void _choose(LocalFood food) {
    setState(() => _highlightedFoodId = food.id);
    widget.onFoodSelected(food.id);
  }

  String get _slotLabel => widget.replacementSide == ComparisonSide.left
      ? 'left'
      : 'right';

  @override
  Widget build(BuildContext context) {
    final List<LocalFood> foods = widget.foods;
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
                  size: AppSizes.iconMedium,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Quick switch',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.accentBrown,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text(
                    '${foods.length} foods more',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick the slot you want to change, then tap a dish below to swap it in.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            // Two clear slot targets - the highlighted (orange) one is what a
            // dish tap will replace.
            Row(
              children: <Widget>[
                Expanded(
                  child: _SlotTile(
                    icon: Icons.view_sidebar_rounded,
                    label: 'Left slot',
                    currentName: widget.leftSlotName,
                    selected: widget.replacementSide == ComparisonSide.left,
                    onTap: () => widget.onSideChanged(ComparisonSide.left),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _SlotTile(
                    icon: Icons.vertical_split_rounded,
                    label: 'Right slot',
                    currentName: widget.rightSlotName,
                    selected: widget.replacementSide == ComparisonSide.right,
                    onTap: () => widget.onSideChanged(ComparisonSide.right),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // A single-line, horizontally scrollable strip keeps this section
            // compact no matter how many foods are selected (10+ included).
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: foods.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (BuildContext context, int index) {
                  final LocalFood food = foods[index];
                  final bool highlighted = food.id == _highlightedFoodId;
                  return ActionChip(
                    tooltip: 'Swap into the $_slotLabel slot',
                    avatar: Icon(
                      Icons.add_circle_outline_rounded,
                      size: 16,
                      color: highlighted
                          ? AppColors.onPrimary
                          : AppColors.textPrimary,
                    ),
                    label: Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlighted
                            ? AppColors.onPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    backgroundColor: highlighted
                        ? AppColors.primary
                        : AppColors.surface,
                    side: BorderSide(
                      color: highlighted
                          ? AppColors.primary
                          : AppColors.outline,
                    ),
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () => _choose(food),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.icon,
    required this.label,
    required this.currentName,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String currentName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = selected
        ? AppColors.onPrimary
        : AppColors.textPrimary;
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outline,
        ),
      ),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                currentName.isEmpty ? 'Empty slot' : currentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
