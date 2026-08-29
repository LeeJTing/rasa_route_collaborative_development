import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/food_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/app_image.dart';
import 'widgets/food_hero_card.dart';
import 'widgets/food_notice_banner.dart';
import 'widgets/food_overview_card.dart';
import 'widgets/food_pairing_list.dart';
import 'widgets/food_section_card.dart';
import 'widgets/recommendation_strip.dart';

class FoodDetailView extends StatefulWidget {
  const FoodDetailView({super.key});

  @override
  State<FoodDetailView> createState() => _FoodDetailViewState();
}

class _FoodDetailViewState extends State<FoodDetailView> {
  late final FoodDetailViewModel _viewModel;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _viewModel = FoodDetailViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final Object? argument = ModalRoute.of(context)?.settings.arguments;
    _viewModel.loadFood(argument is int ? argument : 0);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FoodDetailViewModel>.value(
      value: _viewModel,
      child: Consumer<FoodDetailViewModel>(
        builder: (BuildContext context, FoodDetailViewModel vm, Widget? child) {
          return Scaffold(
            appBar: AppTopBar(
              title: vm.food?.name ?? 'Food Details',
              showBackButton: true,
            ),
            body: _body(context, vm),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, FoodDetailViewModel vm) {
    if (vm.state == ViewState.busy && vm.food == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.state == ViewState.error && vm.food == null) {
      return Center(
        child: ElevatedButton(
          onPressed: () => vm.loadFood(vm.foodId),
          child: Text(vm.errorMessage ?? 'Try again'),
        ),
      );
    }
    final LocalFood? food = vm.food;
    if (food == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: AppSpacing.screenPadding.copyWith(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (vm.allergyWarnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: FoodNoticeBanner(
                message: vm.allergyWarnings.join('\n'),
                type: FoodNoticeType.allergy,
              ),
            ),
          Center(
            child: FoodHeroCard(
              food: food,
              isLiked: vm.isLiked,
              onLike: vm.toggleLike,
              onImageTap: (int initialIndex) =>
                  _showEnlargedImage(context, food, initialIndex),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FoodOverviewCard(
            food: food,
            isStartingPronunciation: vm.isStartingPronunciation,
            onPlayPronunciation: () => _playPronunciation(context, vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          FoodSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _InformationItem(label: 'Description', body: food.description),
                _InformationItem(label: 'Origin', body: food.origin),
                _InformationItem(label: 'Ingredients', body: food.ingredients),
                if (vm.isFoodInformationExpanded)
                  _InformationItem(
                    label: 'Cultural Background',
                    body: food.culturalBackground,
                  ),
                Center(
                  child: IconButton(
                    tooltip: vm.isFoodInformationExpanded
                        ? 'Hide cultural background'
                        : 'Show cultural background',
                    onPressed: vm.toggleFoodInformation,
                    icon: Icon(
                      vm.isFoodInformationExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (vm.collidedFood != null) ...<Widget>[
            FoodSectionCard(
              title: 'Collision Food',
              child: FoodNoticeBanner(
                message:
                    '${food.name} can also refer to ${vm.collidedFood!.name}. Tap to compare the dishes.',
                type: FoodNoticeType.caution,
                onTap: () => vm.loadFood(vm.collidedFood!.id),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          FoodSectionCard(
            title: 'Pairing Recommendations',
            subtitle: 'Flavours that complement this dish',
            child: vm.pairingTimedOut
                ? TextButton.icon(
                    onPressed: vm.retryPairings,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Pairing service timed out — retry'),
                  )
                : FoodPairingList(pairings: vm.foodPairings),
          ),
          const SizedBox(height: AppSpacing.lg),
          FoodSectionCard(
            title: 'Similar Food',
            subtitle: 'Similar local favourites',
            child: RecommendationStrip(
              foods: vm.similarFoods,
              onTap: (LocalFood next) => vm.loadFood(next.id),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEnlargedImage(
    BuildContext context,
    LocalFood food,
    int initialIndex,
  ) => showDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (BuildContext dialogContext) => Dialog(
      insetPadding: EdgeInsets.zero,
      backgroundColor: AppColors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            controller: PageController(initialPage: initialIndex),
            itemCount: food.imageUrls.isEmpty ? 1 : food.imageUrls.length,
            itemBuilder: (BuildContext context, int index) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: AppImage(
                  source: food.imageUrls.isEmpty ? null : food.imageUrls[index],
                  fit: BoxFit.contain,
                  semanticLabel:
                      '${food.name} image ${index + 1} of ${food.imageUrls.length}',
                ),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.lg,
            right: AppSpacing.lg,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Close image',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _playPronunciation(
    BuildContext context,
    FoodDetailViewModel viewModel,
  ) async {
    await viewModel.playPronunciation();
    if (!context.mounted) return;
    final String? message = viewModel.takePronunciationMessage();
    if (message == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InformationItem extends StatelessWidget {
  const _InformationItem({required this.label, required this.body});
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body.isEmpty ? 'Not available' : body,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
