import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/preference_icons.dart';
import '../../domain_model/food_preference.dart';
import '../../view_models/edit_food_preference_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/preference_option_card.dart';

/// Edit the tourist's taste and culture preferences.
///
/// Two cards - Taste Preference and Culture Preference. In each, the chosen
/// options sit on top; a "More options" divider leads to the rest. "Save
/// Changes" persists the choices through the profile logic
/// (`touristLogic.saveFoodPreferences`).
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class EditFoodPreferenceView extends StatefulWidget {
  const EditFoodPreferenceView({super.key});

  @override
  State<EditFoodPreferenceView> createState() => _EditFoodPreferenceViewState();
}

class _EditFoodPreferenceViewState extends State<EditFoodPreferenceView> {
  late final EditFoodPreferenceViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = EditFoodPreferenceViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _save(EditFoodPreferenceViewModel viewModel) async {
    await viewModel.save();
    if (!mounted) return;
    if (viewModel.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            viewModel.errorMessage ?? 'Unable to save. Please try again.',
          ),
        ),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EditFoodPreferenceViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Food Preference'),
        body: SafeArea(
          child: Consumer<EditFoodPreferenceViewModel>(
            builder:
                (
                  BuildContext context,
                  EditFoodPreferenceViewModel viewModel,
                  Widget? _,
                ) {
                  return Column(
                    children: <Widget>[
                      Expanded(
                        child: ListView(
                          padding: AppSpacing.screenPadding,
                          children: <Widget>[
                            _PreferenceCard(
                              icon: Icons.restaurant,
                              title: 'Taste Preference',
                              selectedCount: viewModel.selectedTasteCount,
                              selectedLabels: viewModel.selectedTastes,
                              moreLabels: viewModel.unselectedTastes,
                              isSelected: viewModel.isTasteSelected,
                              onToggle: viewModel.toggleTaste,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _PreferenceCard(
                              icon: Icons.public,
                              title: 'Culture Preference',
                              selectedCount: viewModel.selectedCategoryCount,
                              selectedLabels: viewModel.selectedCategories,
                              moreLabels: viewModel.unselectedCategories,
                              isSelected: viewModel.isCategorySelected,
                              onToggle: viewModel.toggleCategory,
                            ),
                          ],
                        ),
                      ),
                      // Save footer -----------------------------------------
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: const StadiumBorder(),
                          ),
                          onPressed: viewModel.isBusy
                              ? null
                              : () => _save(viewModel),
                          child: const Text('Save Changes'),
                        ),
                      ),
                    ],
                  );
                },
          ),
        ),
      ),
    );
  }
}

/// One group of options (Taste / Culture): title + selected count badge,
/// the chosen options on top, a "More options" divider, then the rest.
///
/// The chevron in the title row switches the option area between that compact
/// two-row layout and ONE vertical grid holding every option - the same grid
/// the dietary-restriction editor uses. Showing both groups compactly on entry
/// keeps taste and culture reachable at a glance, while the grid stays one tap
/// away when the tourist is picking several options in a row.
class _PreferenceCard extends StatefulWidget {
  const _PreferenceCard({
    required this.icon,
    required this.title,
    required this.selectedCount,
    required this.selectedLabels,
    required this.moreLabels,
    required this.isSelected,
    required this.onToggle,
  });

  final IconData icon;
  final String title;
  final int selectedCount;
  final List<FoodPreference> selectedLabels;
  final List<FoodPreference> moreLabels;
  final bool Function(FoodPreference) isSelected;
  final ValueChanged<FoodPreference> onToggle;

  @override
  State<_PreferenceCard> createState() => _PreferenceCardState();
}

class _PreferenceCardState extends State<_PreferenceCard> {
  /// False = the compact layout (two horizontal rows); true = the full grid.
  bool _isExpanded = false;

  void _setExpanded(bool value) {
    if (_isExpanded == value) return;
    setState(() => _isExpanded = value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          widget.icon,
                          size: AppSizes.iconMedium,
                          color: AppColors.accentBrown,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Selected items appear on top',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _SelectedBadge(count: widget.selectedCount),
              // ">" collapses to "v" once the grid is open.
              _ExpandToggle(
                isExpanded: _isExpanded,
                onTap: () => _setExpanded(!_isExpanded),
                semanticLabel: _isExpanded
                    ? 'Collapse ${widget.title}'
                    : 'Show all ${widget.title} options in a grid',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_isExpanded)
            // Selected options stay first, so the grid still reads
            // "selected items appear on top".
            _OptionsGrid(
              labels: <FoodPreference>[
                ...widget.selectedLabels,
                ...widget.moreLabels,
              ],
              isSelected: widget.isSelected,
              onToggle: widget.onToggle,
            )
          else ...<Widget>[
            if (widget.selectedLabels.isNotEmpty) ...<Widget>[
              _OptionsRow(
                labels: widget.selectedLabels,
                isSelected: widget.isSelected,
                onToggle: widget.onToggle,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Row(
              children: <Widget>[
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(
                    'More options',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.accentBrown,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _OptionsRow(
              labels: widget.moreLabels,
              isSelected: widget.isSelected,
              onToggle: widget.onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

/// A horizontally scrollable row of option cards.
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.labels,
    required this.isSelected,
    required this.onToggle,
  });

  final List<FoodPreference> labels;
  final bool Function(FoodPreference) isSelected;
  final ValueChanged<FoodPreference> onToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final FoodPreference preference in labels)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: PreferenceOptionCard(
                label: preference.name,
                iconAsset: PreferenceIcons.foodPreferenceIconAsset(
                  preference.name,
                ),
                isSelected: isSelected(preference),
                onTap: () => onToggle(preference),
                // Keep the option row a uniform height - a long taste/culture
                // name truncates to one line instead of making one card taller.
                maxLabelLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}

/// The expanded layout: every option in ONE vertical grid, identical to the
/// dietary-restriction picker (`EditDietaryRestrictionView`) - 4 per row, a
/// fixed cell height, and long names wrapping inside their cell instead of
/// widening it.
///
/// The grid deliberately does NOT scroll itself: it shares the page's single
/// vertical scroll (shrink-wrapped, never-scrollable), so the arrow expands
/// the card in place rather than opening a second, nested scroll area.
class _OptionsGrid extends StatelessWidget {
  const _OptionsGrid({
    required this.labels,
    required this.isSelected,
    required this.onToggle,
  });

  final List<FoodPreference> labels;
  final bool Function(FoodPreference) isSelected;
  final ValueChanged<FoodPreference> onToggle;

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppLayoutRatios.profileOptionGridCrossAxisCount,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.md,
        // Same fixed cell as the dietary grid, so a two-line name cannot
        // overflow its box.
        mainAxisExtent: AppLayoutRatios.profileOptionGridMainAxisExtent,
      ),
      children: <Widget>[
        for (final FoodPreference preference in labels)
          PreferenceOptionCard(
            label: preference.name,
            iconAsset: PreferenceIcons.foodPreferenceIconAsset(preference.name),
            isSelected: isSelected(preference),
            onTap: () => onToggle(preference),
          ),
      ],
    );
  }
}

/// The ">" / "v" control in a preference card's title row.
///
/// It is a real button (its own tap target with a semantic label), so the
/// arrow can be pressed without toggling an option by mistake. The chevron
/// rotates a quarter turn when the grid opens, so it always points at what the
/// next tap will do.
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({
    required this.isExpanded,
    required this.onTap,
    required this.semanticLabel,
  });

  final bool isExpanded;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        // Transparent, but it MUST be here: the ripple is painted by the
        // nearest Material ancestor, and the card's own surface is opaque - so
        // without this the tap would give no visual feedback at all.
        color: AppColors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            // 24pt glyph + 12pt padding = a 48pt touch target.
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AnimatedRotation(
              turns: isExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.chevron_right,
                size: AppSizes.iconMedium,
                color: AppColors.accentBrown,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "N selected" pill in a card's top-right corner.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      ),
      child: Text(
        '$count selected',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
