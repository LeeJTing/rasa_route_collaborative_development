import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/preference_icons.dart';
import '../../core/view_state.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../view_models/profile_set_up_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/preference_option_card.dart';

/// C3 - first-run profile set-up: food preferences (tastes + cultures) and
/// dietary restrictions, shown BEFORE the dashboard for a brand-new tourist.
///
/// Options come from Supabase (`food_preference` / `dietary_restriction`).
/// Icons are resolved client-side (those tables carry no icon columns) via
/// `PreferenceIcons` - per-option SVGs sourced from online open-source icon
/// sets (Material Design Icons / Phosphor / Lucide-lab).
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class ProfileSetUpView extends StatefulWidget {
  const ProfileSetUpView({super.key});

  @override
  State<ProfileSetUpView> createState() => _ProfileSetUpViewState();
}

class _ProfileSetUpViewState extends State<ProfileSetUpView> {
  late final ProfileSetUpViewModel _viewModel;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileSetUpViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _continue(ProfileSetUpViewModel viewModel) async {
    await viewModel.save();
    if (!mounted || _navigated || !viewModel.saved) return;
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
    _navigated = true;
    // First run complete - land on the shell (same as the OTP/Google paths).
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.mainShell,
      (Route<dynamic> _) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileSetUpViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Set Up Your Profile'),
        body: SafeArea(
          child: Consumer<ProfileSetUpViewModel>(
            builder: (BuildContext context, ProfileSetUpViewModel viewModel, Widget? _) {
              // First load in flight - spinner; load failed - retry.
              if (viewModel.state == ViewState.busy &&
                  viewModel.tasteOptions.isEmpty &&
                  viewModel.dietaryOptions.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (viewModel.hasError &&
                  viewModel.tasteOptions.isEmpty &&
                  viewModel.dietaryOptions.isEmpty) {
                return _LoadError(onRetry: viewModel.load);
              }

              return Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: AppSpacing.screenPadding,
                      children: <Widget>[
                        Text(
                          "Tell us what you like so we can recommend "
                          "the best Malaysian food for you.",
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _SectionCard(
                          icon: Icons.restaurant,
                          title: 'Food Preference',
                          subtitle: 'Pick the tastes and cultures you enjoy.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _OptionHeading('Taste'),
                              const SizedBox(height: AppSpacing.sm),
                              _OptionRow(
                                options: viewModel.tasteOptions,
                                isSelected: viewModel.isPreferenceSelected,
                                onToggle: viewModel.togglePreference,
                                iconAssetFor:
                                    PreferenceIcons.foodPreferenceIconAsset,
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              _OptionHeading('Culture'),
                              const SizedBox(height: AppSpacing.sm),
                              _OptionRow(
                                options: viewModel.categoryOptions,
                                isSelected: viewModel.isPreferenceSelected,
                                onToggle: viewModel.togglePreference,
                                iconAssetFor:
                                    PreferenceIcons.foodPreferenceIconAsset,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _SectionCard(
                          icon: Icons.no_food,
                          title: 'Dietary Restrictions',
                          subtitle:
                              'Anything you avoid - the app will filter '
                              'foods accordingly.',
                          child: viewModel.dietaryOptions.isEmpty
                              ? Text(
                                  'No dietary restrictions available yet.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.textDisabled),
                                )
                              : GridView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: AppLayoutRatios
                                            .profileOptionGridCrossAxisCount,
                                        mainAxisSpacing: AppSpacing.lg,
                                        crossAxisSpacing: AppSpacing.md,
                                        mainAxisExtent: AppLayoutRatios
                                            .profileOptionGridMainAxisExtent,
                                      ),
                                  children: <Widget>[
                                    for (final DietaryRestriction r
                                        in viewModel.dietaryOptions)
                                      PreferenceOptionCard(
                                        label: r.name,
                                        iconAsset:
                                            PreferenceIcons.dietaryRestrictionIconAsset(
                                              r.name,
                                            ),
                                        isSelected: viewModel.isDietarySelected(
                                          r,
                                        ),
                                        onTap: () => viewModel.toggleDietary(r),
                                      ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                  // Continue footer ------------------------------------
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: ElevatedButton(
                      onPressed: viewModel.canContinue
                          ? () => _continue(viewModel)
                          : null,
                      style: ElevatedButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      child: viewModel.state == ViewState.busy
                          ? const CircularProgressIndicator()
                          : const Text('Continue'),
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

/// One white card with an icon + title + subtitle header, containing the
/// option rows/grid for one profile section.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
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
            children: <Widget>[
              Icon(
                icon,
                size: AppSizes.iconMedium,
                color: AppColors.accentBrown,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Small section heading inside a card ("Taste", "Culture").
class _OptionHeading extends StatelessWidget {
  const _OptionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: AppColors.accentBrown,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Horizontally scrollable row of selectable option cards.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.options,
    required this.isSelected,
    required this.onToggle,
    required this.iconAssetFor,
  });

  final List<FoodPreference> options;
  final bool Function(FoodPreference) isSelected;
  final ValueChanged<FoodPreference> onToggle;
  final String? Function(String name) iconAssetFor;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Text(
        'No options available yet.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textDisabled),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final FoodPreference option in options)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: PreferenceOptionCard(
                label: option.name,
                iconAsset: iconAssetFor(option.name),
                isSelected: isSelected(option),
                onTap: () => onToggle(option),
                // One line keeps every card the same height in the row.
                maxLabelLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the options could not be loaded - message + Retry.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off,
              size: AppSizes.iconMedium,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            const Text("Couldn't load your profile options."),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
