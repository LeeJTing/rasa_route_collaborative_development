import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/profile_set_up_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Set up your taste screen.
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
/// in `profile_set_up_view/widgets/`.
class ProfileSetUpView extends StatefulWidget {
  const ProfileSetUpView({super.key});

  @override
  State<ProfileSetUpView> createState() => _ProfileSetUpViewState();
}

class _ProfileSetUpViewState extends State<ProfileSetUpView> {
  late final ProfileSetUpViewModel _viewModel;

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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ProfileSetUpViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Set up your taste'),
        body: SafeArea(
          child: Consumer<ProfileSetUpViewModel>(
            builder: (BuildContext context, ProfileSetUpViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('ProfileSetUpView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
