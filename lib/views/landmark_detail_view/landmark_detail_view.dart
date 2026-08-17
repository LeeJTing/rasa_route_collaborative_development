import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/landmark_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Landmark screen.
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
/// in `landmark_detail_view/widgets/`.
class LandmarkDetailView extends StatefulWidget {
  const LandmarkDetailView({super.key});

  @override
  State<LandmarkDetailView> createState() => _LandmarkDetailViewState();
}

class _LandmarkDetailViewState extends State<LandmarkDetailView> {
  late final LandmarkDetailViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkDetailViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkDetailViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Landmark'),
        body: SafeArea(
          child: Consumer<LandmarkDetailViewModel>(
            builder: (BuildContext context, LandmarkDetailViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('LandmarkDetailView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
