import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../domain_model/food_comparison.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/food_comparison_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import 'widgets/comparison_insight_card.dart';
import 'widgets/comparison_notice.dart';
import 'widgets/comparison_pair_card.dart';
import 'widgets/quick_switcher_bar.dart';

class FoodComparisonView extends StatefulWidget {
  const FoodComparisonView({super.key});

  @override
  State<FoodComparisonView> createState() => _FoodComparisonViewState();
}

class _FoodComparisonViewState extends State<FoodComparisonView> {
  late final FoodComparisonViewModel _viewModel;
  bool _loadedArguments = false;

  @override
  void initState() {
    super.initState();
    _viewModel = FoodComparisonViewModel();
    _viewModel.onInit();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedArguments) {
      return;
    }
    _loadedArguments = true;
    final Object? arguments = ModalRoute.of(context)?.settings.arguments;
    final List<int> selectedFoodIds = arguments is List<Object?>
        ? arguments.whereType<int>().toList(growable: false)
        : const <int>[];
    _viewModel.loadSelectedFoodIds(selectedFoodIds);
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
      child: Consumer<FoodComparisonViewModel>(
        builder: (
          BuildContext context,
          FoodComparisonViewModel viewModel,
          Widget? child,
        ) {
          return Scaffold(
          appBar: AppTopBar(
          title: 'Food Comparison',
          showBackButton: true,
          ),
            body: _body(viewModel),
          );
        },
      ),
    );
  }

  Widget _body(FoodComparisonViewModel viewModel) {
    final FoodComparison? comparison = viewModel.comparison;
    if (viewModel.isBusy && comparison == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.hasError && comparison == null) {
      return AsyncMessage(
        icon: Icons.compare_arrows_rounded,
        title: 'Comparison unavailable',
        message: viewModel.errorMessage ??
            'Select at least ${viewModel.minimumSelection} local foods.',
        actionLabel: 'Back to local foods',
        onAction: viewModel.goBack,
      );
    }
    if (comparison == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSizes.comparisonMaxWidth,
            ),
            child: ListView(
              padding: AppSpacing.screenPadding,
              children: <Widget>[
                const ComparisonNotice(),
                if (viewModel.quickSwitcherFoods.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  QuickSwitcherBar(
                    foods: viewModel.quickSwitcherFoods,
                    replacementSide: viewModel.replacementSide,
                    leftSlotName: comparison.leftFood.name,
                    rightSlotName: comparison.rightFood.name,
                    onSideChanged: viewModel.chooseReplacementSide,
                    onFoodSelected: viewModel.replaceWith,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                ComparisonInsightCard(
                  comparison: comparison,
                  bestValueFood: viewModel.bestValueFood,
                ),
                const SizedBox(height: AppSpacing.md),
                ComparisonPairCard(
                  comparison: comparison,
                  onPlayPronunciation: (LocalFood food) =>
                      _playPronunciation(context, viewModel, food),
                  playingPronunciationFoodIds:
                      viewModel.playingPronunciationFoodIds,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
        if (viewModel.isSwitching) const LinearProgressIndicator(),
      ],
    );
  }

  /// Plays a dish's pronunciation and surfaces any device/unavailable message
  /// after it finishes (reuses the food-detail flow).
  Future<void> _playPronunciation(
    BuildContext context,
    FoodComparisonViewModel viewModel,
    LocalFood food,
  ) async {
    await viewModel.playPronunciation(food);
    if (!mounted) return;
    final String? message = viewModel.takePronunciationMessage();
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
