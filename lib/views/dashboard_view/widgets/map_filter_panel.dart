import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/exploration_filter.dart';

/// Smart Filtering - the dropdown, multiple-row filter selection bar
/// (REQ102_23, A7).
///
/// One row per group: a fixed labelpill ("Meal", "Category", "Taste",
/// "Type"), a separator, then the options as chips. Collapsed, a row scrolls
/// horizontally exactly as in the Figma frame; the chevron expands it into a
/// wrap so every option is reachable - the Taste group alone has 23 of them
/// (REQ102_26).
///
/// **As many options per group as the tourist wants.** A chip toggles itself
/// on and off and its neighbours are left alone, so Breakfast *and* Lunch can
/// both be lit. Within a row that reads as "or"; across rows as "and". The
/// "All" chip at the head of each row unticks the whole row, and is lit
/// whenever nothing in the row is.
///
/// **Nothing happens until Apply.** The chips edit a draft the ViewModel holds;
/// Apply hands it to the map in a single request and closes the panel, Cancel
/// throws it away and leaves the active filter alone. This is why the footer is
/// pinned rather than scrolled with the rows: it is the only way out that
/// changes anything, and it has to stay in sight.
///
/// **The panel is capped and scrolls.** Expanded, a row wraps its options onto
/// as many lines as it needs, and Taste alone has 23 of them - four groups open
/// at once ran past the bottom of the screen, which took the panel's own
/// controls with it. The rows now scroll inside
/// `AppSizes.filterPanelMaxHeight` and the footer stays pinned below them, so
/// there is always somewhere to finish and always a way out.
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
    required this.selectionCount,
    required this.onToggleOption,
    required this.onClearGroup,
    required this.onToggleExpanded,
    required this.onApply,
    required this.onCancel,
  });

  final String Function(ExplorationFilterGroup group) labelFor;
  final List<String> Function(ExplorationFilterGroup group) optionsFor;

  /// Everything ticked in a group. Empty is "All".
  final Set<String> Function(ExplorationFilterGroup group) selectionFor;
  final bool Function(ExplorationFilterGroup group) isExpanded;

  /// Chips ticked across all four groups, for the Apply button's count.
  final int selectionCount;

  final void Function(ExplorationFilterGroup group, String option)
  onToggleOption;
  final ValueChanged<ExplorationFilterGroup> onClearGroup;
  final ValueChanged<ExplorationFilterGroup> onToggleExpanded;

  /// Hand the draft to the map - the only call here that costs a request.
  final VoidCallback onApply;

  /// Leave without applying; the filter the map already has stays.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // Opaque on purpose. Without this a tap that lands between two chips falls
    // through to the map underneath, whose onTap closes the filter panel - so
    // every near-miss dismissed the whole thing.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: AppSizes.filterPanelMaxHeight,
        ),
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
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final ExplorationFilterGroup group
                        in ExplorationFilterGroup.values)
                      _FilterGroupSection(
                        label: labelFor(group),
                        options: optionsFor(group),
                        selection: selectionFor(group),
                        expanded: isExpanded(group),
                        onToggleOption: (String option) =>
                            onToggleOption(group, option),
                        onClearGroup: () => onClearGroup(group),
                        onToggleExpanded: () => onToggleExpanded(group),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: AppSpacing.md, color: AppColors.outline),
            Row(
              children: <Widget>[
                Text(
                  selectionCount == 0
                      ? 'No filters selected'
                      : '$selectionCount selected',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _PanelButton(
                  label: 'Cancel',
                  filled: false,
                  onTap: onCancel,
                ),
                const SizedBox(width: AppSpacing.sm),
                _PanelButton(label: 'Apply', filled: true, onTap: onApply),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _FilterGroupSection extends StatelessWidget {
  const _FilterGroupSection({
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
  final Set<String> selection;
  final bool expanded;
  final ValueChanged<String> onToggleOption;
  final VoidCallback onClearGroup;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[
      _FilterChip(
        label: 'All',
        selected: selection.isEmpty,
        onTap: onClearGroup,
      ),
      for (final String option in options)
        _FilterChip(
          label: option,
          selected: selection.contains(option),
          onTap: () => onToggleOption(option),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Text(
                    label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: AppSizes.inlineNoticeIconSize,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (expanded)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: chips,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < chips.length; i++) ...<Widget>[
                    chips[i],
                    if (i < chips.length - 1)
                      const SizedBox(width: AppSpacing.sm),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
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
    borderRadius: BorderRadius.circular(AppRadius.pill),
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
  );
}

/// Apply and Cancel. Styled like the chips above rather than as Material
/// buttons, so the footer reads as part of the same panel.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: filled ? AppColors.primary : AppColors.outline,
        ),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: filled ? AppColors.onPrimary : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
