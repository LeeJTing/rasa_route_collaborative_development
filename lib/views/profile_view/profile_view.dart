import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../view_models/profile_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Profile screen.
///
/// Placeholder body. What is wired up is the View - ViewModel connection:
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
///
/// Build the layout from the Figma frame for this screen, using
/// `Theme.of(context)` and the tokens in `lib/app/theme/`. Reusable pieces go
/// in `profile_view/widgets/`.
class ProfileView extends StatefulWidget {
  const ProfileView({super.key});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  late final ProfileViewModel _viewModel;

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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Profile'),
        body: SafeArea(
          child: Consumer<ProfileViewModel>(
            builder:
                (BuildContext context, ProfileViewModel viewModel, Widget? _) {
                  return ListView(
                    padding: AppSpacing.screenPadding,
                    children: <Widget>[
                      const Text(
                        'Contributions',
                        style: AppTextStyles.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // The tourist's submitted landmarks - opens the full
                      // contribution history (one tourist can add many).
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(
                            Icons.place_outlined,
                            color: AppColors.primary,
                          ),
                          title: const Text('Submitted Landmarks'),
                          subtitle: const Text(
                            'Landmarks you have added to the map',
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: viewModel.openSubmittedLandmarks,
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
