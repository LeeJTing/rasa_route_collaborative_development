import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../view_models/food_recommendation_view_model.dart';
import '../common_widgets/food_pairing_card.dart';

class FoodRecommendationView extends StatefulWidget {
  const FoodRecommendationView({super.key, this.foodId});
  final int? foodId;

  @override
  State<FoodRecommendationView> createState() => _FoodRecommendationViewState();
}

class _FoodRecommendationViewState extends State<FoodRecommendationView> {
  late final FoodRecommendationViewModel _viewModel;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _viewModel = FoodRecommendationViewModel();
  }

  int get _foodId {
    if (widget.foodId != null) return widget.foodId!;
    final Object? argument = ModalRoute.of(context)?.settings.arguments;
    return argument is int ? argument : 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    _viewModel.foodId = _foodId;
    _viewModel.onInit();
  }

  @override
  void didUpdateWidget(FoodRecommendationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.foodId != oldWidget.foodId) {
      _viewModel.load(_foodId);
    }
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
      child: Consumer<FoodRecommendationViewModel>(
        builder:
            (BuildContext context, FoodRecommendationViewModel vm, Widget? _) {
              return _content(context, vm);
            },
      ),
    );
  }

  Widget _content(BuildContext context, FoodRecommendationViewModel vm) {
    if (vm.state == ViewState.busy && vm.selectedFood == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.state == ViewState.error && vm.selectedFood == null) {
      return Center(
        child: ElevatedButton(
          onPressed: () => vm.load(vm.foodId),
          child: Text(vm.errorMessage ?? 'Try again'),
        ),
      );
    }
    if (vm.loadingPairings) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.pairingTimedOut) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextButton.icon(
            onPressed: vm.retryPairings,
            icon: const Icon(Icons.refresh),
            label: const Text("Couldn't load pairings — retry"),
          ),
          if (vm.pairingError != null && vm.pairingError!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                vm.pairingError!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      );
    }
    if (vm.pairings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'No suitable food pairings were found for your dietary requirements.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: vm.pairings
          .map(
            (pairing) => FoodPairingCard(
              pairing: pairing,
              pairedFood: vm.pairedFood(pairing.pairedLocalFoodId),
              onTap: () => Navigator.pushNamed(
                context,
                AppRoutes.foodDetail,
                arguments: pairing.pairedLocalFoodId,
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
