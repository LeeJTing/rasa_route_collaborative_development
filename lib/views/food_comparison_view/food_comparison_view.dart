import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/food_comparison_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Compare screen.
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
/// in `food_comparison_view/widgets/`.
class FoodComparisonView extends StatefulWidget {
  const FoodComparisonView({super.key});

  @override
  State<FoodComparisonView> createState() => _FoodComparisonViewState();
}

class _FoodComparisonViewState extends State<FoodComparisonView> {
  late final FoodComparisonViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = FoodComparisonViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FoodComparisonViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Compare'),
        body: SafeArea(
          child: Consumer<FoodComparisonViewModel>(
            builder: (BuildContext context, FoodComparisonViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('FoodComparisonView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
