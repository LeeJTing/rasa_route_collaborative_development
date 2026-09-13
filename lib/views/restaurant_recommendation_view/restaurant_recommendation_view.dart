import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rasa_route_collaborative_development/views/restaurant_recommendation_view/widgets/submmitted_landmark_card.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../view_models/dashboard_view_model.dart';
import '../../view_models/restaurant_recommendation_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/enlarged_image_dialog.dart';
import 'widgets/restaurant_card.dart';
import 'widgets/restaurant_food_type_filter.dart';

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
          onProfileTap: () async {
            await Navigator.pushNamed(context, AppRoutes.profile);
            await _viewModel.refreshAfterProfileChange();
          },
        ),
        body: Consumer<RestaurantRecommendationViewModel>(
          builder:
              (
                BuildContext context,
                RestaurantRecommendationViewModel vm,
                Widget? child,
              ) {
                return Column(
                  children: <Widget>[
                    const _NearbyBanner(),

                    _SourceTabs(source: vm.source, onChanged: vm.selectSource),

                    RestaurantFoodTypeFilter(
                      options:
                          RestaurantRecommendationViewModel.foodTypeOptions,
                      selected: vm.selectedFoodType,
                      onSelected: vm.selectFoodType,
                    ),

                    Expanded(
                      child: vm.isLoadingResult
                          ? const Center(child: CircularProgressIndicator())
                          : vm.state == ViewState.error &&
                                vm.selectedSourceIsEmpty
                          ? AsyncMessage(
                              icon: Icons.location_off_outlined,
                              title: 'Unable to load nearby places',
                              message:
                                  vm.errorMessage ??
                                  'Check your connection and location, then try again.',
                              actionLabel: 'Try again',
                              onAction: vm.loadNearbyRestaurants,
                            )
                          : vm.selectedSourceIsEmpty
                          ? _EmptySource(source: vm.source)
                          : ListView.separated(
                              padding: AppSpacing.screenPadding.copyWith(
                                bottom: AppSpacing.xl,
                              ),
                              itemCount: vm.source == RestaurantSource.google
                                  ? vm.visibleRestaurants.length
                                  : vm.landmarks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (BuildContext context, int index) {
                                if (vm.source == RestaurantSource.google) {
                                  final Restaurant restaurant =
                                      vm.visibleRestaurants[index];

                                  return RestaurantCard(
                                    restaurant: restaurant,
                                    distanceLabel: vm.distanceLabel(restaurant),
                                    expanded: vm.isRestaurantExpanded(
                                      restaurant.id,
                                    ),
                                    onExpand: () => vm.toggleRestaurantExpanded(
                                      restaurant.id,
                                    ),
                                    onTap: () => Navigator.pushNamed(
                                      context,
                                      AppRoutes.restaurantDetail,
                                      arguments: restaurant.id,
                                    ),
                                    onFoodImageTap: (RestaurantItem item) =>
                                        showRestaurantItemImage(
                                          context,
                                          semanticLabel: item.foodName,
                                          source: item.imageUrl,
                                          fromLinkedFood:
                                              item.imageFromLinkedFood,
                                        ),
                                  );
                                }

                                final SubmittedLandmarkRecommendation landmark =
                                    vm.landmarks[index];

                                return SubmittedLandmarkCard(
                                  landmark: landmark,
                                  expanded: vm.isLandmarkExpanded(landmark.id),
                                  onExpand: () =>
                                      vm.toggleLandmarkExpanded(landmark.id),
                                  onTap: () =>
                                      _openLandmarkDetails(context, landmark),
                                  onImageTap:
                                      (String? source, String semanticLabel) =>
                                          showEnlargedImage(
                                            context,
                                            semanticLabel: semanticLabel,
                                            source: source,
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
          icon: Icon(Icons.restaurant_outlined),
          label: Text('Restaurants'),
        ),
        ButtonSegment(
          value: RestaurantSource.submitted,
          icon: Icon(Icons.add_location_alt_outlined),
          label: Text('Submitted Landmarks'),
        ),
      ],
      selected: <RestaurantSource>{source},
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          Theme.of(context).textTheme.labelMedium,
        ),
        visualDensity: VisualDensity.compact,
      ),
      onSelectionChanged: (Set<RestaurantSource> value) =>
          onChanged(value.first),
    ),
  );
}

class _EmptySource extends StatelessWidget {
  const _EmptySource({required this.source});

  final RestaurantSource source;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppSpacing.screenPadding,
      child: Text(
        source == RestaurantSource.submitted
            ? 'No open submitted landmarks matching your dietary restrictions were found within 10 km.'
            : 'No open restaurants matching your dietary restrictions were found within 10 km.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
