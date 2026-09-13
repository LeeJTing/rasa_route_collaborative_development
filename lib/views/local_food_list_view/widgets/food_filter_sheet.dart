import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// Presentation-only filter group; the owning View supplies current values
/// and forwards callbacks to its ViewModel.
class FoodFilterSection {
  const FoodFilterSection({
    required this.title,
    required this.values,
    required this.isSelected,
    required this.onToggle,
  });

  final String title;
  final List<String> values;
  final bool Function(String) isSelected;
  final ValueChanged<String> onToggle;
}

class FoodFilterSheet extends StatelessWidget {
  const FoodFilterSheet({
    super.key,
    required this.controller,
    required this.sections,
    required this.resultCount,
    required this.onApply,
    required this.onClear,
  });

  final ScrollController controller;
  final List<FoodFilterSection> sections;
  final int resultCount;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListView(
    controller: controller,
    padding: const EdgeInsets.all(AppSpacing.lg),
    children: <Widget>[
      Text('Filter local food', style: Theme.of(context).textTheme.titleLarge),
      ...sections.map((FoodFilterSection section) => _FilterGroup(section)),
      const SizedBox(height: AppSpacing.xl),
      Row(
        children: <Widget>[
          Expanded(
            child: ElevatedButton(
              onPressed: resultCount == 0 ? null : onApply,
              child: Text(
                'Show $resultCount local food',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ElevatedButton(
              onPressed: onClear,
              child: const Text('Clear'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
    ],
  );
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup(this.section);

  final FoodFilterSection section;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(section.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: section.values
              .map((String value) {
                final bool selected = section.isSelected(value);
                return FilterChip(
                  label: Text(value),
                  selected: selected,
                  onSelected: (_) => section.onToggle(value),
                  selectedColor: AppColors.primary,
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? AppColors.onPrimary
                        : AppColors.textPrimary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  checkmarkColor: AppColors.onPrimary,
                  side: BorderSide(
                    color: selected ? AppColors.primary : AppColors.outline,
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    ),
  );
}
