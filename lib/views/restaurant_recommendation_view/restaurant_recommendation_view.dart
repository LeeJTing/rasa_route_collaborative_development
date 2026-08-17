import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/restaurant_recommendation_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Near you screen.
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
/// in `restaurant_recommendation_view/widgets/`.
class RestaurantRecommendationView extends StatefulWidget {
  const RestaurantRecommendationView({super.key});

  @override
  State<RestaurantRecommendationView> createState() => _RestaurantRecommendationViewState();
}

class _RestaurantRecommendationViewState extends State<RestaurantRecommendationView> {
  late final RestaurantRecommendationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RestaurantRecommendationViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RestaurantRecommendationViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Near you'),
        body: SafeArea(
          child: Consumer<RestaurantRecommendationViewModel>(
            builder: (BuildContext context, RestaurantRecommendationViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('RestaurantRecommendationView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
