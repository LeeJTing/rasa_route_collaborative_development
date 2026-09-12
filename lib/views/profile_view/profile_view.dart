import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../view_models/profile_view_model.dart';
import '../common_widgets/app_tag_chip.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/profile_chip_row.dart';
import 'widgets/profile_email_card.dart';
import 'widgets/profile_link_item.dart';
import 'widgets/profile_section_card.dart';

/// Profile screen.
///
/// Two editable cards (Food Preference, Dietary Restriction) followed by
/// links to the Favourite Food collection, My Landmarks (the landmark module's
/// contribution history) and Log Out - matching the "User Profile" mock-up.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final ProfileViewModel _viewModel;
  bool _isReturning = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  void _returnToDashboard() {
    if (_isReturning) return;
    setState(() => _isReturning = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop(_viewModel.discoverySettingsChanged);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileViewModel>.value(
      value: _viewModel,
      child: PopScope(
        canPop: _isReturning,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) return;
          _returnToDashboard();
        },
        child: Scaffold(
          appBar: AppTopBar(title: 'User Profile', onBack: _returnToDashboard),
          body: SafeArea(
            child: Consumer<ProfileViewModel>(
              builder:
                  (
                    BuildContext context,
                    ProfileViewModel viewModel,
                    Widget? _,
                  ) {
                    return ListView(
                      padding: AppSpacing.screenPadding,
                      children: <Widget>[
                        // Email -----------------------------------------------
                        // While the first load is in flight the email is still
                        // empty, so show a loader rather than briefly flashing
                        // the misleading "Not signed in" fallback.
                        ProfileEmailCard(
                          email: viewModel.email,
                          isLoading:
                              viewModel.state == ViewState.busy &&
                              viewModel.email.isEmpty,
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Food Preference -------------------------------------
                        ProfileSectionCard(
                          title: 'Food Preference',
                          onEdit: viewModel.openFoodPreference,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _SubSectionTitle('Taste'),
                              const SizedBox(height: AppSpacing.sm),
                              ProfileChipRow(
                                labels: viewModel.preferredTastes,
                                style: AppTagStyle.taste,
                                emptyHint: 'No taste preferences selected yet.',
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Divider(),
                              const SizedBox(height: AppSpacing.md),
                              _SubSectionTitle('Culture'),
                              const SizedBox(height: AppSpacing.sm),
                              ProfileChipRow(
                                labels: viewModel.preferredCategories,
                                style: AppTagStyle.category,
                                emptyHint:
                                    'No culture preferences selected yet.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Dietary Restriction --------------------------------
                        ProfileSectionCard(
                          title: 'Dietary Restriction',
                          onEdit: viewModel.openDietaryRestriction,
                          child: ProfileChipRow(
                            labels: viewModel.dietaryRestrictions
                                .map((DietaryRestriction r) => r.name)
                                .toList(growable: false),
                            style: AppTagStyle.dietary,
                            emptyHint: 'No dietary restrictions set yet.',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // Links ------------------------------------------------
                        ProfileLinkItem(
                          icon: Icons.favorite,
                          iconColor: AppColors.error,
                          label: 'Favourite Foods',
                          onTap: viewModel.openFavouriteCollection,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileLinkItem(
                          icon: Icons.place_outlined,
                          iconColor: AppColors.textPrimary,
                          label: 'My Landmarks',
                          onTap: viewModel.openSubmittedLandmarks,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileLinkItem(
                          icon: Icons.assignment_outlined,
                          iconColor: AppColors.textPrimary,
                          label: 'Incomplete Submissions',
                          onTap: viewModel.openIncompleteLandmarks,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileLinkItem(
                          icon: Icons.logout,
                          iconColor: AppColors.textPrimary,
                          label: 'Log Out',
                          showChevron: false,
                          onTap: viewModel.signOut,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    );
                  },
            ),
          ),
        ),
      ),
    );
  }
}

/// The small accent-brown heading above a chip group ("Taste", "Culture").
class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: AppColors.accentBrown,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
