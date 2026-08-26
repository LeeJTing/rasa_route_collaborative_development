import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/exploration_filter.dart';

/// Smart Filtering - the dropdown, multiple-row filter selection bar
/// (REQ102_23, A7).
///
/// One row per group: a fixed label pill ("Meal", "Category", "Taste",
/// "Type"), a separator, then the options as chips. Collapsed, a row scrolls
/// horizontally exactly as in the Figma frame; the chevron expands it into a
/// wrap so every option is reachable - the Taste group alone has 23 of them
/// (REQ102_26).
///
/// **One option per group.** Picking a different chip replaces the current
/// choice; picking the chip already chosen clears the group. The "All" chip at
/// the head of each row does the same thing explicitly, and is selected
/// whenever the group is unset - so the row behaves like a radio group and
/// needs no separate reset.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class MapFilterPanel extends StatelessWidget {
  const MapFilterPanel({
    super.key,
    required this.labelFor,
    required this.optionsFor,
    required this.selectionFor,
    required this.isExpanded,
    required this.onToggleOption,
    required this.onClearGroup,
    required this.onToggleExpanded,
  });

  final String Function(ExplorationFilterGroup group) labelFor;
  final List<String> Function(ExplorationFilterGroup group) optionsFor;
  final String? Function(ExplorationFilterGroup group) selectionFor;
  final bool Function(ExplorationFilterGroup group) isExpanded;

  final void Function(ExplorationFilterGroup group, String option)
  onToggleOption;
  final ValueChanged<ExplorationFilterGroup> onClearGroup;
  final ValueChanged<ExplorationFilterGroup> onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    // Opaque on purpose. Without this a tap that lands between two chips falls
    // through to the map underneath, whose onTap closes the filter panel - so
    // every near-miss dismissed the whole thing.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.outline),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final ExplorationFilterGroup group
                in ExplorationFilterGroup.values)
              _FilterRow(
                label: labelFor(group),
                options: optionsFor(group),
                selection: selectionFor(group),
                expanded: isExpanded(group),
                onToggleOption: (String option) => onToggleOption(group, option),
                onClearGroup: () => onClearGroup(group),
                onToggleExpanded: () => onToggleExpanded(group),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.options,
    required this.selection,
    required this.expanded,
    required this.onToggleOption,
    required this.onClearGroup,
    required this.onToggleExpanded,
  });

  final String label;
  final List<String> options;
  final String? selection;
  final bool expanded;
  final ValueChanged<String> onToggleOption;
  final VoidCallback onClearGroup;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      _FilterChip(
        label: 'All',
        selected: selection == null,
        onTap: onClearGroup,
      ),
      for (final String option in options)
        _FilterChip(
          label: option,
          selected: selection == option,
          onTap: () => onToggleOption(option),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: AppSizes.filterGroupLabelWidth,
            height: AppSizes.filterChipTapHeight,
            child: Center(
              child: _GroupLabel(label: label, selected: selection != null),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            width: 1,
            height: AppSizes.filterChipHeight,
            color: AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: expanded
                ? Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: 0,
                    children: chips,
                  )
                : SizedBox(
                    height: AppSizes.filterChipTapHeight,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: chips.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (_, int index) => chips[index],
                    ),
                  ),
          ),
          InkWell(
            onTap: onToggleExpanded,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    height: AppSizes.filterChipHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: selected ? AppColors.primaryContainer : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textPrimary),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    // The tap area is taller than the pill it draws. Filter chips are tapped
    // repeatedly - one after another across four rows - so the target has to
    // forgive a few pixels.
    child: SizedBox(
      height: AppSizes.filterChipTapHeight,
      child: Center(
        child: Container(
          height: AppSizes.filterChipHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outline,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );
}
