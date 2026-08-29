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
                    Expanded(
                      child: vm.restaurants.isEmpty
                          ? const _EmptySource()
                          : ListView.separated(
                              padding: AppSpacing.screenPadding.copyWith(
                                bottom: AppSpacing.xl,
                              ),
                              itemCount: vm.restaurants.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (BuildContext context, int index) {
                                final restaurant = vm.restaurants[index];
                                return RestaurantCard(
                                  restaurant: restaurant,
                                  distanceLabel: vm.distanceLabel(restaurant),
                                  expanded: vm.isExpanded(restaurant.id),
                                  onExpand: () =>
                                      vm.toggleExpanded(restaurant.id),
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.restaurantDetail,
                                    arguments: restaurant.id,
                                  ),
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
    child: Row(
      children: <Widget>[
        const SizedBox.square(
          dimension: AppSizes.bannerIcon,
          child: CircleAvatar(
            backgroundColor: AppColors.success,
            child: Icon(Icons.check, color: AppColors.onPrimary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Showing Nearby Restaurants',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.bannerInfoText,
                ),
              ),
              Text(
                'Sorted by nearest distance',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.bannerInfoText,
                ),
              ),
            ],
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
          label: Text('Google-Sourced Restaurant'),
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
