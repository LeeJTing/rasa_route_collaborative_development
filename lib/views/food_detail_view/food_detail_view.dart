import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/local_food.dart';
import '../../view_models/food_detail_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/food_hero_card.dart';
import 'widgets/food_notice_banner.dart';
import 'widgets/food_pairing_list.dart';
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
    _viewModel.loadFood(argument is int ? argument : 1);
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
          ...vm.allergyWarnings.map(
            (String warning) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: FoodNoticeBanner(
                message: warning,
                type: FoodNoticeType.allergy,
              ),
            ),
          ),
          Center(
            child: FoodHeroCard(
              food: food,
              isLiked: vm.isLiked,
              onLike: vm.toggleLike,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _PronunciationCard(food: food),
          const SizedBox(height: AppSpacing.xl),
          _Section(title: 'Description', body: food.description),
          _Section(title: 'Origin', body: food.origin),
          _Section(title: 'Ingredients', body: food.ingredients),
          _Section(title: 'Cultural Background', body: food.culturalBackground),
          if (vm.collidedFood != null) ...<Widget>[
            FoodNoticeBanner(
              message:
                  '${food.name} can also refer to ${vm.collidedFood!.name}. Tap to compare the dishes.',
              type: FoodNoticeType.caution,
              onTap: () => vm.loadFood(vm.collidedFood!.id),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          _Heading(
            title: 'Best Pairings',
            subtitle: 'Flavours that complement this dish',
          ),
          if (vm.pairingTimedOut)
            TextButton.icon(
              onPressed: vm.retryPairings,
              icon: const Icon(Icons.refresh),
              label: const Text('Pairing service timed out — retry'),
            )
          else
            FoodPairingList(pairings: vm.foodPairings),
          const SizedBox(height: AppSpacing.lg),
          const _Heading(
            title: 'You might also like',
            subtitle: 'Similar local favourites',
          ),
          RecommendationStrip(
            foods: vm.similarFoods,
            onTap: (LocalFood next) => vm.loadFood(next.id),
          ),
        ],
      ),
    );
  }
}

class _PronunciationCard extends StatelessWidget {
  const _PronunciationCard({required this.food});
  final LocalFood food;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: AppSpacing.cardPadding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.cardBorderWarm),
      borderRadius: AppRadius.cardRadius,
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.volume_up_outlined, color: AppColors.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Pronunciation',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                food.pronunciationText.isEmpty
                    ? food.name
                    : food.pronunciationText,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (food.synonyms.isNotEmpty)
                Text(
                  'Also known as ${food.synonyms.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
