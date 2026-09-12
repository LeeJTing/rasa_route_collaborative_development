import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/preference_icons.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../view_models/edit_dietary_restriction_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/preference_option_card.dart';

/// Edit the tourist's dietary restrictions.
///
/// "Chosen on top" repeats the selected options for quick access; "All
/// Restrictions" is the full picker grid. "Save Changes" persists the choices
/// through the profile logic (`touristLogic.saveDietaryRestrictions`).
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class EditDietaryRestrictionView extends StatefulWidget {
  const EditDietaryRestrictionView({super.key});

  @override
  State<EditDietaryRestrictionView> createState() =>
      _EditDietaryRestrictionViewState();
}

class _EditDietaryRestrictionViewState
    extends State<EditDietaryRestrictionView> {
  late final EditDietaryRestrictionViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = EditDietaryRestrictionViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _save(EditDietaryRestrictionViewModel viewModel) async {
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
    return ChangeNotifierProvider<EditDietaryRestrictionViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Dietary Restriction'),
        body: SafeArea(
          child: Consumer<EditDietaryRestrictionViewModel>(
            builder:
                (
                  BuildContext context,
                  EditDietaryRestrictionViewModel viewModel,
                  Widget? _,
                ) {
                  return Column(
                    children: <Widget>[
                      Expanded(
                        child: ListView(
                          padding: AppSpacing.screenPadding,
                          children: <Widget>[
                            _RestrictionCard(
                              icon: Icons.auto_awesome,
                              title: 'Chosen on top',
                              subtitle:
                                  'Your selected items will appear here for easy access.',
                              badgeCount: viewModel.selectedCount,
                              child: viewModel.selectedRestrictions.isEmpty
                                  ? Text(
                                      'Nothing selected yet.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.textDisabled,
                                          ),
                                    )
                                  : GridView(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: AppLayoutRatios
                                                .profileOptionGridCrossAxisCount,
                                            mainAxisSpacing: AppSpacing.lg,
                                            crossAxisSpacing: AppSpacing.md,
                                            // Same fixed cell as "All
                                            // Restrictions": 4 per row, and a
                                            // long name wraps inside the cell
                                            // instead of widening its card and
                                            // pushing the next one down a row.
                                            mainAxisExtent: AppLayoutRatios
                                                .profileOptionGridMainAxisExtent,
                                          ),
                                      children: <Widget>[
                                        for (final DietaryRestriction r
                                            in viewModel.selectedRestrictions)
                                          PreferenceOptionCard(
                                            label: r.name,
                                            iconAsset:
                                                PreferenceIcons.dietaryRestrictionIconAsset(
                                                  r.name,
                                                ),
                                            isSelected: true,
                                            onTap: () => viewModel.toggle(r),
                                          ),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _RestrictionCard(
                              icon: Icons.lunch_dining,
                              title: 'All Restrictions',
                              // Show WHY the grid is empty instead of a blank
                              // card - a load error and an unseeded table look
                              // identical otherwise.
                              child: viewModel.restrictions.isEmpty
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          viewModel.hasError
                                              ? "Couldn't load the list of "
                                                    'dietary restrictions.'
                                              : 'No dietary restrictions '
                                                    'available yet.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppColors.textDisabled,
                                              ),
                                        ),
                                        // Show the REAL failure (e.g. "column
                                        // X does not exist" / "permission
                                        // denied") so a missing junction table
                                        // or RLS policy is diagnosable instead
                                        // of a generic empty card.
                                        if (viewModel.hasError &&
                                            viewModel.errorMessage != null) ...[
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            viewModel.errorMessage!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: AppColors.error,
                                                ),
                                          ),
                                        ],
                                        if (viewModel.hasError)
                                          TextButton(
                                            onPressed: viewModel.load,
                                            child: const Text('Retry'),
                                          ),
                                      ],
                                    )
                                  : GridView(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: AppLayoutRatios
                                                .profileOptionGridCrossAxisCount,
                                            mainAxisSpacing: AppSpacing.lg,
                                            crossAxisSpacing: AppSpacing.md,
                                            // Fixed height so long names wrap
                                            // over two lines without
                                            // overflowing the cell.
                                            mainAxisExtent: AppLayoutRatios
                                                .profileOptionGridMainAxisExtent,
                                          ),
                                      children: <Widget>[
                                        for (final DietaryRestriction r
                                            in viewModel.restrictions)
                                          PreferenceOptionCard(
                                            label: r.name,
                                            iconAsset:
                                                PreferenceIcons.dietaryRestrictionIconAsset(
                                                  r.name,
                                                ),
                                            isSelected: viewModel.isSelected(r),
                                            onTap: () => viewModel.toggle(r),
                                          ),
                                      ],
                                    ),
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

/// A white rounded card: title row (icon + title + optional subtitle and
/// count badge) with the card's content underneath.
class _RestrictionCard extends StatelessWidget {
  const _RestrictionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.badgeCount,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int? badgeCount;
  final Widget child;

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
                          icon,
                          size: AppSizes.iconMedium,
                          color: AppColors.accentBrown,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (badgeCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadius.pill),
                    ),
                  ),
                  child: Text(
                    '$badgeCount selected',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
