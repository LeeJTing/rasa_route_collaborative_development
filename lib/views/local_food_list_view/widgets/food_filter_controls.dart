import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

class FoodFilterControls extends StatelessWidget {
  const FoodFilterControls({
    super.key,
    required this.isSelecting,
    required this.activeFilterCount,
    required this.onSort,
    required this.onFilter,
    required this.onSelect,
    required this.onReset,
  });

  final bool isSelecting;
  final int activeFilterCount;
  final VoidCallback onSort;
  final VoidCallback onFilter;
  final VoidCallback onSelect;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _Control(label: 'Sort', icon: Icons.swap_vert, onTap: onSort),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Control(
            label: activeFilterCount == 0
                ? 'Filter'
                : 'Filter ($activeFilterCount)',
            icon: Icons.tune,
            onTap: onFilter,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Control(
            label: isSelecting ? 'Done' : 'Select',
            icon: isSelecting ? Icons.check : Icons.check_box_outlined,
            selected: isSelecting,
            onTap: onSelect,
          ),
        ),
        TextButton(onPressed: onReset, child: const Text('Reset')),
      ],
    );
  }
}

class _Control extends StatelessWidget {
  const _Control({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.compactControlHeight,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: AppSizes.iconCompact),
        label: Text(label, maxLines: 1),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected
              ? AppColors.primaryContainer
              : AppColors.surface,
          minimumSize: const Size(0, AppSizes.compactControlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
      ),
    );
  }
}
