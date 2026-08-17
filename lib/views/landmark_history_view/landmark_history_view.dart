import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/landmark_history_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// My contributions screen.
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
/// in `landmark_history_view/widgets/`.
class LandmarkHistoryView extends StatefulWidget {
  const LandmarkHistoryView({super.key});

  @override
  State<LandmarkHistoryView> createState() => _LandmarkHistoryViewState();
}

class _LandmarkHistoryViewState extends State<LandmarkHistoryView> {
  late final LandmarkHistoryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkHistoryViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkHistoryViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'My contributions'),
        body: SafeArea(
          child: Consumer<LandmarkHistoryViewModel>(
            builder: (BuildContext context, LandmarkHistoryViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('LandmarkHistoryView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
