import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../view_models/restaurant_recommendation_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/restaurant_card.dart';

class RestaurantRecommendationView extends StatefulWidget {
  const RestaurantRecommendationView({super.key});

  @override
  State<RestaurantRecommendationView> createState() =>
      _RestaurantRecommendationViewState();
}

class _RestaurantRecommendationViewState
    extends State<RestaurantRecommendationView> {
  late final RestaurantRecommendationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = RestaurantRecommendationViewModel()..onInit();
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
        appBar: AppTopBar(
          title: 'Quick Mode',
          showBackButton: true,
          onProfileTap: () => Navigator.pushNamed(context, AppRoutes.profile),
        ),
        body: Consumer<RestaurantRecommendationViewModel>(
          builder:
              (
                BuildContext context,
                RestaurantRecommendationViewModel vm,
                Widget? child,
              ) {
                if (vm.state == ViewState.busy && vm.restaurants.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vm.state == ViewState.error && vm.restaurants.isEmpty) {
                  return Center(
                    child: ElevatedButton(
                      onPressed: vm.loadNearbyRestaurants,
                      child: Text(vm.errorMessage ?? 'Try again'),
                    ),
                  );
                }
                return Column(
                  children: <Widget>[
                    const _NearbyBanner(),
                    _SourceTabs(source: vm.source, onChanged: vm.selectSource),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Row(
                        children: <Widget>[
                          Text('${vm.restaurants.length} restaurants nearby'),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: vm.toggleDistanceSort,
                            icon: const Icon(Icons.sort),
                            label: Text(
                              vm.isAscending
                                  ? 'Nearest first'
                                  : 'Farthest first',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: vm.restaurants.isEmpty
                          ? const _EmptySource()
                          : ListView.separated(
                              padding: AppSpacing.screenPadding.copyWith(
                                bottom: AppSpacing.xl,
                              ),
                              itemCount: vm.restaurants.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (BuildContext context, int index) {
                                if (index == vm.restaurants.length) {
                                  return TextButton.icon(
                                    onPressed: vm.isLoadingMore
                                        ? null
                                        : vm.loadMoreRestaurants,
                                    icon: vm.isLoadingMore
                                        ? const SizedBox.square(
                                            dimension: AppSpacing.lg,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.add_location_alt_outlined,
                                          ),
                                    label: Text(
                                      'Expand search to ${(vm.searchRadius + 1).clamp(1, 10).toStringAsFixed(0)} km',
                                    ),
                                  );
                                }
                                final restaurant = vm.restaurants[index];
                                return RestaurantCard(
                                  restaurant: restaurant,
                                  expanded: vm.isExpanded(restaurant.id),
                                  onExpand: () =>
                                      vm.toggleExpanded(restaurant.id),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
        ),
      ),
    );
  }
}

class _NearbyBanner extends StatelessWidget {
  const _NearbyBanner();

  @override
  Widget build(BuildContext context) => Container(
    margin: AppSpacing.screenPadding,
    padding: AppSpacing.cardPadding,
    decoration: BoxDecoration(
      color: AppColors.bannerInfoBackground,
      borderRadius: AppRadius.cardRadius,
    ),
    child: const Row(
      children: <Widget>[
        Icon(Icons.near_me_outlined, color: AppColors.bannerInfoIcon),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'Showing nearby restaurants based on your current location.',
            style: TextStyle(color: AppColors.bannerInfoText),
          ),
        ),
      ],
    ),
  );
}

class _SourceTabs extends StatelessWidget {
  const _SourceTabs({required this.source, required this.onChanged});
  final RestaurantSource source;
  final ValueChanged<RestaurantSource> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: AppSpacing.screenPadding,
    child: SegmentedButton<RestaurantSource>(
      segments: const <ButtonSegment<RestaurantSource>>[
        ButtonSegment(
          value: RestaurantSource.google,
          label: Text('Google-Sourced'),
        ),
        ButtonSegment(
          value: RestaurantSource.submitted,
          label: Text('Submitted Landmark'),
        ),
      ],
      selected: <RestaurantSource>{source},
      onSelectionChanged: (Set<RestaurantSource> value) =>
          onChanged(value.first),
    ),
  );
}

class _EmptySource extends StatelessWidget {
  const _EmptySource();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: AppSpacing.screenPadding,
      child: Text('No submitted restaurant landmarks are available yet.'),
    ),
  );
}
