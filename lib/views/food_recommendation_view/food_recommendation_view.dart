import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/food_recommendation_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// For you screen.
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
/// in `food_recommendation_view/widgets/`.
class FoodRecommendationView extends StatefulWidget {
  const FoodRecommendationView({super.key});

  @override
  State<FoodRecommendationView> createState() => _FoodRecommendationViewState();
}

class _FoodRecommendationViewState extends State<FoodRecommendationView> {
  late final FoodRecommendationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = FoodRecommendationViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FoodRecommendationViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'For you'),
        body: SafeArea(
          child: Consumer<FoodRecommendationViewModel>(
            builder:
                (
                  BuildContext context,
                  FoodRecommendationViewModel viewModel,
                  Widget? _,
                ) {
                  return const Padding(
                    padding: AppSpacing.screenPadding,
                    child: Center(child: Text('FoodRecommendationView')),
                  );
                },
          ),
        ),
      ),
    );
  }
}
