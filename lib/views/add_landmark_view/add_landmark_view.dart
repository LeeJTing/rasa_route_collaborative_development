import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/add_landmark_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Add a landmark screen.
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
/// in `add_landmark_view/widgets/`.
class AddLandmarkView extends StatefulWidget {
  const AddLandmarkView({super.key});

  @override
  State<AddLandmarkView> createState() => _AddLandmarkViewState();
}

class _AddLandmarkViewState extends State<AddLandmarkView> {
  late final AddLandmarkViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = AddLandmarkViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddLandmarkViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Add a landmark'),
        body: SafeArea(
          child: Consumer<AddLandmarkViewModel>(
            builder:
                (
                  BuildContext context,
                  AddLandmarkViewModel viewModel,
                  Widget? _,
                ) {
                  return const Padding(
                    padding: AppSpacing.screenPadding,
                    child: Center(child: Text('AddLandmarkView')),
                  );
                },
          ),
        ),
      ),
    );
  }
}
