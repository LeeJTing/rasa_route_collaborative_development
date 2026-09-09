import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/view_state.dart';
import '../../domain_model/matches_recommendation.dart';
import '../../domain_model/restaurant_item.dart';
import '../../view_models/dashboard_view_model.dart';
import '../../view_models/restaurant_recommendation_view_model.dart';
import '../common_widgets/app_image.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
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
                if (vm.state == ViewState.busy &&
                    vm.restaurants.isEmpty &&
                    vm.landmarks.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vm.state == ViewState.error &&
                    vm.restaurants.isEmpty &&
                    vm.landmarks.isEmpty) {
                  return AsyncMessage(
                    icon: Icons.location_off_outlined,
                    title: 'Unable to load nearby places',
                    message:
                        vm.errorMessage ??
                        'Check your connection and location, then try again.',
                    actionLabel: 'Try again',
                    onAction: vm.loadNearbyRestaurants,
                  );
                }
                return Column(
                  children: <Widget>[
                    const _NearbyBanner(),
                    _SourceTabs(source: vm.source, onChanged: vm.selectSource),
                    Expanded(
                      child: vm.selectedSourceIsEmpty
                          ? _EmptySource(source: vm.source)
                          : ListView.separated(
                              padding: AppSpacing.screenPadding.copyWith(
                                bottom: AppSpacing.xl,
                              ),
                              itemCount: vm.source == RestaurantSource.google
                                  ? vm.restaurants.length
                                  : vm.landmarks.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.md),
                              itemBuilder: (BuildContext context, int index) {
                                if (vm.source == RestaurantSource.google) {
                                  final restaurant = vm.restaurants[index];
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
                                        _showEnlargedImage(
                                          context,
                                          item.imageUrl,
                                          item.foodName,
                                        ),
                                  );
                                }
                                final SubmittedLandmarkRecommendation landmark =
                                    vm.landmarks[index];
                                return _SubmittedLandmarkCard(
                                  landmark: landmark,
                                  expanded: vm.isLandmarkExpanded(landmark.id),
                                  onExpand: () =>
                                      vm.toggleLandmarkExpanded(landmark.id),
                                  onTap: () =>
                                      _openLandmarkDetails(context, landmark),
                                  onImageTap: () => _showEnlargedImage(
                                    context,
                                    landmark.imageUrl,
                                    landmark.name,
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

  Future<void> _showEnlargedImage(
    BuildContext context,
    String? source,
    String semanticLabel,
  ) {
    if (source?.trim().isNotEmpty != true) return Future<void>.value();
    return showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (BuildContext dialogContext) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: AppColors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: AppImage(
                  source: source,
                  fit: BoxFit.contain,
                  semanticLabel: semanticLabel,
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

class _SubmittedLandmarkCard extends StatelessWidget {
  const _SubmittedLandmarkCard({
    required this.landmark,
    required this.expanded,
    required this.onExpand,
    required this.onTap,
    required this.onImageTap,
  });

  final SubmittedLandmarkRecommendation landmark;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onTap;
  final VoidCallback onImageTap;

  static const int _previewLimit = 4;

  @override
  Widget build(BuildContext context) {
    final List<String> preview = landmark.foodNames
        .take(_previewLimit)
        .toList(growable: false);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardRadius,
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: AppSpacing.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                InkWell(
                  onTap: landmark.imageUrl?.trim().isNotEmpty == true
                      ? onImageTap
                      : null,
                  borderRadius: AppRadius.cardRadius,
                  child: SizedBox.square(
                    dimension: AppSizes.restaurantCardImage,
                    child: AppImage(
                      source: landmark.imageUrl,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: landmark.name,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: AppRadius.cardRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            landmark.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (landmark.category.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              landmark.category,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: <Widget>[
                              const Icon(
                                Icons.location_on_outlined,
                                size: AppSizes.iconCompact,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(_distanceLabel(landmark.distanceMetres)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (expanded)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.insetSurface,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (preview.isEmpty)
                    Text(
                      'Food details are not available yet.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...preview.map(
                      (String foodName) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          foodName,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ),
                  if (landmark.foodNames.length > _previewLimit)
                    Center(
                      child: Text(
                        'Showing $_previewLimit of ${landmark.foodNames.length} local foods · Tap the landmark for all',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          IconButton(
            tooltip: expanded ? 'Hide local food' : 'Show local food',
            onPressed: onExpand,
            icon: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
          ),
        ],
      ),
    );
  }

  static String _distanceLabel(double metres) {
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }
}
