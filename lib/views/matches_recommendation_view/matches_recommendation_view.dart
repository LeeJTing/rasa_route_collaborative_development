import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/matches_recommendation_tab.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../view_models/dashboard_view_model.dart' show MapSelectionHandoff;
import '../../view_models/matches_recommendation_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/matched_food_recommendation_group.dart';
import 'widgets/matches_recommendation_tabs.dart';
import 'widgets/matches_restaurant_card.dart';
import 'widgets/submitted_landmark_recommendation_card.dart';

class MatchesRecommendationView extends StatefulWidget {
  const MatchesRecommendationView({super.key});

  @protected
  MatchesRecommendationViewModel createViewModel() =>
      MatchesRecommendationViewModel();

  @override
  State<MatchesRecommendationView> createState() =>
      _MatchesRecommendationViewState();
}

class _MatchesRecommendationViewState extends State<MatchesRecommendationView> {
  late final MatchesRecommendationViewModel _viewModel;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.createViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    final Object? arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is MatchesRecommendationRequest) {
      _viewModel.configureRequest(arguments);
    }
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ChangeNotifierProvider<MatchesRecommendationViewModel>.value(
    value: _viewModel,
    child: Scaffold(
      appBar: const AppTopBar(title: 'Matches', showBackButton: true),
      body: SafeArea(
        child: Consumer<MatchesRecommendationViewModel>(
          builder:
              (
                BuildContext context,
                MatchesRecommendationViewModel viewModel,
                Widget? _,
              ) => Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          viewModel.stateName.isEmpty
                              ? 'Recommendations from your active Swipe Mode state.'
                              : '${viewModel.stateName} recommendations from foods you liked.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MatchesRecommendationTabs(
                          selectedTab: viewModel.selectedTab,
                          onChanged: viewModel.selectTab,
                        ),
                      ],
                    ),
                  ),
                  _SortToolbar(viewModel: viewModel),
                  Expanded(child: _buildContent(context, viewModel)),
                ],
              ),
        ),
      ),
    ),
  );

  Widget _buildContent(
    BuildContext context,
    MatchesRecommendationViewModel viewModel,
  ) {
    if (viewModel.state == ViewState.busy && viewModel.groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.state == ViewState.error && viewModel.groups.isEmpty) {
      return _RetryState(
        message: viewModel.errorMessage ?? 'Recommendations could not load.',
        onRetry: viewModel.loadRecommendations,
      );
    }
    if (!viewModel.hasLikedFoods) {
      return const _NoLikesState();
    }

    final List<MatchedFoodRecommendations> groups = viewModel.displayedGroups;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (BuildContext context, int index) {
        final MatchedFoodRecommendations group = groups[index];
        final bool restaurants =
            viewModel.selectedTab == MatchesRecommendationTab.restaurants;
        // Build a real Widget list. A conditional expression can otherwise
        // retain the branch's narrower runtime type (for example,
        // List<MatchesRestaurantCard>) and reject the empty-state widget.
        final List<Widget> cards = <Widget>[
          ...(restaurants
              ? _restaurantCards(context, group)
              : _landmarkCards(context, group)),
        ];
        if (cards.isEmpty) {
          cards.add(
            _GroupEmptyState(
              type: restaurants ? 'restaurants' : 'submitted landmarks',
              radiusKm: viewModel.radiusFor(group.food.id),
            ),
          );
        }
        return MatchedFoodRecommendationGroup(
          key: ValueKey<String>(
            'match-group-${group.food.id}-${viewModel.selectedTab.name}',
          ),
          food: group.food,
          resultCount: restaurants
              ? group.restaurants.length
              : group.submittedLandmarks.length,
          onFoodTap: () => Navigator.pushNamed(
            context,
            AppRoutes.foodDetail,
            arguments: group.food.id,
          ),
          onLikeTap: () => viewModel.removeMatchedFood(group.food.id),
          radiusKm: viewModel.radiusFor(group.food.id),
          canShowMore: viewModel.canShowMore(group.food.id),
          canShowLess: viewModel.canShowLess(group.food.id),
          isLoadingMore: viewModel.isLoadingMore(group.food.id),
          onShowMore: () => viewModel.showMore(group.food.id),
          onShowLess: () => viewModel.showLess(group.food.id),
          children: cards,
        );
      },
    );
  }

  List<Widget> _restaurantCards(
    BuildContext context,
    MatchedFoodRecommendations group,
  ) => group.restaurants
      .map(
        (restaurant) => MatchesRestaurantCard(
          restaurant: restaurant,
          matchedFoodName: group.food.name,
          startingPrice: group.restaurantStartingPrices[restaurant.id],
          onTap: () => _openRestaurantDetails(context, restaurant.id),
        ),
      )
      .toList(growable: true);

  /// Restaurant reporting can change a place from `available` to `frozen`
  /// while this Matches route remains mounted. Reload after the detail route
  /// returns so a newly hidden restaurant is removed without requiring the
  /// tourist to leave and reopen Matches.
  Future<void> _openRestaurantDetails(
    BuildContext context,
    int restaurantId,
  ) async {
    await Navigator.pushNamed(
      context,
      AppRoutes.restaurantDetail,
      arguments: restaurantId,
    );
    if (!mounted) return;
    await _viewModel.loadRecommendations();
  }

  List<Widget> _landmarkCards(
    BuildContext context,
    MatchedFoodRecommendations group,
  ) => group.submittedLandmarks
      .map(
        (SubmittedLandmarkRecommendation landmark) =>
            SubmittedLandmarkRecommendationCard(
              landmark: landmark,
              onTap: () => _openLandmarkDetails(context, landmark),
            ),
      )
      .toList(growable: true);

  void _openLandmarkDetails(
    BuildContext context,
    SubmittedLandmarkRecommendation landmark,
  ) {
    if (landmark.id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Landmark details are unavailable.')),
      );
      return;
    }
    MapSelectionHandoff().pendingLandmarkId = landmark.id;
    Navigator.pushNamed(context, AppRoutes.landmarkPlaceDetail);
  }
}

class _SortToolbar extends StatelessWidget {
  const _SortToolbar({required this.viewModel});

  final MatchesRecommendationViewModel viewModel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${viewModel.displayedResultCount} recommendations shown',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                viewModel.selectedTab == MatchesRecommendationTab.restaurants
                ? _restaurantSortChips(context, viewModel)
                : _landmarkSortChips(context, viewModel),
          ),
        ),
      ],
    ),
  );

  List<Widget> _restaurantSortChips(
    BuildContext context,
    MatchesRecommendationViewModel viewModel,
  ) => MatchesRestaurantSort.values
      .map((MatchesRestaurantSort sort) {
        final bool selected = viewModel.restaurantSort == sort;
        return _paddedChip(
          ChoiceChip(
            selected: selected,
            onSelected: (_) => viewModel.selectRestaurantSort(sort),
            backgroundColor: AppColors.surfaceVariant,
            selectedColor: AppColors.primary,
            checkmarkColor: AppColors.onPrimary,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.outline,
            ),
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            label: _SortLabel(
              text: switch (sort) {
                MatchesRestaurantSort.distance => 'Distance',
                MatchesRestaurantSort.price => 'Price',
                MatchesRestaurantSort.preference => 'Preference',
                MatchesRestaurantSort.rating => 'Rating',
              },
              direction: selected ? viewModel.restaurantSortDirection : null,
            ),
          ),
        );
      })
      .toList(growable: false);

  List<Widget> _landmarkSortChips(
    BuildContext context,
    MatchesRecommendationViewModel viewModel,
  ) => MatchesLandmarkSort.values
      .map((MatchesLandmarkSort sort) {
        final bool selected = viewModel.landmarkSort == sort;
        return _paddedChip(
          ChoiceChip(
            selected: selected,
            onSelected: (_) => viewModel.selectLandmarkSort(sort),
            backgroundColor: AppColors.surfaceVariant,
            selectedColor: AppColors.primary,
            checkmarkColor: AppColors.onPrimary,
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.outline,
            ),
            labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
            label: _SortLabel(
              text: switch (sort) {
                MatchesLandmarkSort.distance => 'Distance',
                MatchesLandmarkSort.price => 'Price',
                MatchesLandmarkSort.name => 'Name',
              },
              direction: selected ? viewModel.landmarkSortDirection : null,
            ),
          ),
        );
      })
      .toList(growable: false);

  Widget _paddedChip(Widget chip) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.sm),
    child: chip,
  );
}

class _SortLabel extends StatelessWidget {
  const _SortLabel({required this.text, this.direction});

  final String text;
  final MatchesSortDirection? direction;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(text),
      if (direction != null) ...<Widget>[
        const SizedBox(width: AppSpacing.xs),
        Icon(
          direction == MatchesSortDirection.ascending
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          size: AppSpacing.lg,
        ),
      ],
    ],
  );
}

class _NoLikesState extends StatelessWidget {
  const _NoLikesState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.favorite_border,
            size: AppSizes.avatarMd,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No matched foods yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Double tap a food in Swipe Mode. Only liked foods appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class _GroupEmptyState extends StatelessWidget {
  const _GroupEmptyState({required this.type, required this.radiusKm});

  final String type;
  final double radiusKm;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.sm),
    child: Text(
      'No matching $type within ${radiusKm.toStringAsFixed(0)} km.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
