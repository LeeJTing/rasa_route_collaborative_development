import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../view_models/food_recommendation_view_model.dart';
import '../common_widgets/food_notice_banner.dart';
import '../common_widgets/food_pairing_card.dart';
import '../common_widgets/food_section_card.dart';
import '../common_widgets/similar_food_card.dart';

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
    // The two sections always render; each loading/error/empty state is shown
    // INSIDE its section so the embedded widget never blanks out the page.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FoodSectionCard(
          title: 'Pairing Recommendations',
          subtitle: 'Flavours that complement this dish',
          child: _pairingSection(context, vm),
        ),
        const SizedBox(height: AppSpacing.lg),
        FoodSectionCard(
          title: 'Similar Food',
          subtitle: 'Similar local favourites',
          child: SimilarFoodCard(
            foods: vm.similarFoods,
            onTap: (food) => Navigator.pushNamed(
              context,
              AppRoutes.foodDetail,
              arguments: food.id,
            ),
          ),
        ),
      ],
    );
  }

  /// The Pairing Recommendations section body. The loading animation, retry,
  /// empty and fallback-banner states live here - only this section's content
  /// changes while the pairings load, never the whole page.
  Widget _pairingSection(
    BuildContext context,
    FoodRecommendationViewModel vm,
  ) {
    // The selected dish is still being resolved - small inline spinner.
    if (vm.selectedFood == null && vm.state == ViewState.busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (vm.selectedFood == null && vm.state == ViewState.error) {
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'No suitable food pairings were found for your dietary requirements.',
        ),
      );
    }
    final String? fallbackModel = vm.pairingFallbackModel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (fallbackModel != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FoodNoticeBanner(
              message:
                  'The main AI service is busy right now — these pairings '
                  'were generated with a fallback model and may be less '
                  'tailored than usual.',
              type: FoodNoticeType.degraded,
            ),
          ),
        ...vm.pairings.map(
          (pairing) => FoodPairingCard(
            pairing: pairing,
            pairedFood: vm.pairedFood(pairing.pairedLocalFoodId),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.foodDetail,
              arguments: pairing.pairedLocalFoodId,
            ),
          ),
        ),
      ],
    );
  }
}
