import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/config/env.dart';
import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/map.dart';
import '../../domain_model/region.dart';
import '../../view_models/dashboard_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import 'widgets/discovery_layer_bar.dart';
import 'widgets/map_controls.dart';
import 'widgets/map_filter_panel.dart';
import 'widgets/map_search_bar.dart';
import 'widgets/map_search_results_panel.dart';
import 'widgets/map_update_banner.dart';
import 'widgets/heatmap_scale.dart';
import 'widgets/map_selection_cards.dart';
import 'widgets/region_heatmap_layer.dart';

/// REQ102 - the Local Food Dashboard & Regional Exploration Module, following
/// UC300 "Get Restaurant Information".
///
/// One OpenStreetMap surface with two faces, swapped automatically once the
/// map crosses the predefined zoom level (REQ102_12, REQ102_13) - a decision
/// the ViewModel makes and this View is simply told about:
///
///   * **Heatmap view** (REQ102_15) - all 16 Malaysian states shaded green to
///     grey by their local food availability score, with the Smart Filtering
///     panel (REQ102_23) and the whole-country fallback of REQ102_14.
///   * **Detailed map view** (REQ102_12) - restaurant and submitted-landmark
///     pins, the Swipe Mode panel (REQ102_10) and the Quick Mode button
///     (REQ102_11).
///
/// The View owns the `MapController` because that is a piece of widget
/// machinery, not state; the ViewModel *requests* a camera position and this
/// State applies it, then reports back what the map actually settled on. That
/// keeps `DashboardViewModel` free of Flutter, as the guideline requires.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  late final DashboardViewModel _viewModel;
  final MapController _mapController = MapController();

  /// Reaches [RegionHeatmapCanvasState.scaleBy] so the shared "+" / "-"
  /// buttons drive the painted overview as well as the slippy map.
  final GlobalKey<RegionHeatmapCanvasState> _heatmapKey =
      GlobalKey<RegionHeatmapCanvasState>();
  final TextEditingController _searchController = TextEditingController();

  bool _mapReady = false;
  int _appliedCameraRevision = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = DashboardViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// Applies a camera request once per revision, after the frame that
  /// announced it - moving a `MapController` during `build` is not allowed.
  void _applyCameraRequest(DashboardViewModel viewModel) {
    if (!_mapReady) return;
    if (viewModel.cameraRevision == _appliedCameraRevision) return;
    _appliedCameraRevision = viewModel.cameraRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(
        LatLng(viewModel.cameraLatitude, viewModel.cameraLongitude),
        viewModel.cameraZoom,
      );
    });
  }

  /// The search field is the View's own widget, so it has to be kept in step
  /// when the ViewModel changes the keyword itself (a picked result, A8.3).
  void _syncSearchField(DashboardViewModel viewModel) {
    if (_searchController.text == viewModel.searchKeyword) return;
    _searchController.value = TextEditingValue(
      text: viewModel.searchKeyword,
      selection: TextSelection.collapsed(
        offset: viewModel.searchKeyword.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: AppTopBar(
          title: 'Dashboard',
          showBackButton: false,
          onProfileTap: _viewModel.openProfile,
        ),
        body: Consumer<DashboardViewModel>(
          builder:
              (BuildContext context, DashboardViewModel viewModel, Widget? _) {
                _applyCameraRequest(viewModel);
                _syncSearchField(viewModel);

                return Column(
                  children: <Widget>[
                    _searchRow(viewModel),
                    Expanded(child: _mapArea(context, viewModel)),
                  ],
                );
              },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Search row (A8) - above the map, exactly as in both Figma frames.
  // ---------------------------------------------------------------------------

  Widget _searchRow(DashboardViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: MapSearchBar(
        controller: _searchController,
        onChanged: viewModel.updateSearchKeyword,
        onSubmitted: viewModel.submitSearch,
        onClear: viewModel.clearSearch,
        onTap: viewModel.openSearchPanel,
        // Offered on both surfaces. The filter narrows the same food selection
        // either way - the heatmap's scores on one, the pins on the other - and
        // `_applyFilter` already reloads whichever view is showing, so gating
        // it to the heatmap only hid a control that worked.
        onFilterTap: viewModel.toggleFilterPanel,
        filterCount: viewModel.filter.selectionCount,
        filterPanelOpen: viewModel.filterPanelOpen,
      ),
    );
  }

  /// How much of the map the Swipe Mode sheet is covering right now.
  double _swipePanelHeight(DashboardViewModel viewModel) =>
      viewModel.swipePanelExpanded
      ? AppSizes.discoveryLayerBarHeight
      : AppSizes.discoveryLayerBarCollapsedHeight;

  /// REQ102_3 - one "+". In the overview that scales the painted canvas; in
  /// the detailed view it moves the map camera.
  void _zoomIn(DashboardViewModel viewModel) {
    if (viewModel.isHeatmapView) {
      _heatmapKey.currentState?.scaleBy(1.6);
      return;
    }
    viewModel.zoomIn();
  }

  /// REQ102_5 - one "-".
  void _zoomOut(DashboardViewModel viewModel) {
    if (viewModel.isHeatmapView) {
      _heatmapKey.currentState?.scaleBy(1 / 1.6);
      return;
    }
    viewModel.zoomOut();
  }

  // ---------------------------------------------------------------------------
  // The map and everything floating over it
  // ---------------------------------------------------------------------------

  Widget _mapArea(BuildContext context, DashboardViewModel viewModel) {
    // The map is a rounded card on the cream scaffold rather than a full-bleed
    // surface - it is what the mock-up shows, and it keeps the floating
    // controls, the legend and the bottom sheets visibly *on* the map instead
    // of hovering over the whole screen. Everything below is inside the clip,
    // so nothing can escape the card.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.mapCardRadius),
          border: Border.all(color: AppColors.outline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.mapCardRadius),
          child: _mapStack(context, viewModel),
        ),
      ),
    );
  }

  Widget _mapStack(BuildContext context, DashboardViewModel viewModel) {
    return Stack(
      children: <Widget>[
        // Two different surfaces, not two layers of one: the overview is a
        // painted, stylised Malaysia and the detailed view is OpenStreetMap.
        // `RegionHeatmapCanvas` explains why.
        Positioned.fill(
          child: viewModel.isHeatmapView
              ? RegionHeatmapCanvas(
                  key: _heatmapKey,
                  regions: viewModel.regionScores,
                  outlines: viewModel.countryOutlines,
                  selectedRegionCode: viewModel.selectedRegion?.region.code,
                  onRegionTap: viewModel.selectRegion,
                  onZoomedIntoRegion: viewModel.onHeatmapZoomedInto,
                  onScaleChanged: viewModel.onHeatmapScaleChanged,
                  detailScale: viewModel.heatmapDetailScale,
                  resetToken: viewModel.heatmapResetToken,
                  // REQ102_7 / A3 - shown only when the fix is known *and*
                  // inside Malaysia. This map covers one country; a dot for a
                  // tourist in Singapore or Jakarta would be drawn at whatever
                  // the stylised projection maps their coordinates to, which is
                  // somewhere in Malaysia. Better to show nothing than to show
                  // them somewhere they are not.
                  touristLatitude: viewModel.showCurrentLocation
                      ? viewModel.location.latitude
                      : null,
                  touristLongitude: viewModel.showCurrentLocation
                      ? viewModel.location.longitude
                      : null,
                )
              : _map(viewModel),
        ),

        if (viewModel.isHeatmapView)
          Positioned(
            left: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: HeatmapLegend(
              maximumPlaceCount: viewModel.distribution.maximumPlaceCount,
            ),
          ),

        // REQ102_3 / REQ102_5 / REQ102_9 - the floating control column, bottom
        // right. It lifts above the Discovery Layer Bar in the detailed view so
        // the swipe panel never covers it.
        Positioned(
          right: AppSpacing.lg,
          bottom: viewModel.showSwipePanel
              ? _swipePanelHeight(viewModel) + AppSpacing.sm
              : AppSpacing.lg,
          child: Column(
            children: <Widget>[
              MapZoomControl(
                onZoomIn: () => _zoomIn(viewModel),
                onZoomOut: () => _zoomOut(viewModel),
                canZoomIn: viewModel.canZoomIn,
                canZoomOut: viewModel.canZoomOut,
              ),
              if (viewModel.showFindMeButton) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                MapFindMeButton(
                  onTap: viewModel.locateTourist,
                  busy: viewModel.locating,
                ),
              ],
              // Presenter tool (dev builds only, Android only): teleports the
              // OS-level GPS so the map can be demoed "at" a preset spot
              // without moving the device. Wired through the ViewModel so this
              // View never touches a shared client (see `DashboardViewModel`).
              if (Env.appEnv != 'prod' &&
                  viewModel.mockGpsSupported) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _MockGpsButton(viewModel: viewModel),
              ],
            ],
          ),
        ),

        // A9 - tapping obtains a fresh GPS fix before navigation.
        if (viewModel.showQuickModeButton)
          Positioned(
            left: AppSpacing.lg,
            bottom: _swipePanelHeight(viewModel) + AppSpacing.sm,
            child: MapQuickModeButton(onTap: () => viewModel.openQuickMode()),
          ),

        // REQ102_10 - the Swipe Mode panel.
        if (viewModel.showSwipePanel)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DiscoveryLayerBar(
              expanded: viewModel.swipePanelExpanded,
              onToggle: viewModel.toggleSwipePanel,
              contextLabel: viewModel.contextLabel,
              matchesCount: viewModel.matchesCount,
              currentFood: viewModel.currentSwipeFood,
              previousFood: viewModel.previousSwipeFood,
              nextFood: viewModel.nextSwipeFood,
              currentFoodRestricted: viewModel.currentSwipeFoodRestricted,
              currentFoodLiked: viewModel.currentSwipeFoodLiked,
              loading: viewModel.swipeLoading,
              errorMessage: viewModel.swipeError,
              showResumePrompt: viewModel.showSwipeResumePrompt,
              stateName: viewModel.swipeStateName,
              savedCardCount: viewModel.savedSwipeCardCount,
              savedLikeCount: viewModel.savedSwipeLikeCount,
              savedRestaurantCount: viewModel.savedSwipeRestaurantCount,
              likeRevision: viewModel.swipeLikeRevision,
              onPrevious: viewModel.showPreviousSwipeFood,
              onNext: viewModel.showNextSwipeFood,
              onFoodTap: (food) => Navigator.pushNamed(
                context,
                AppRoutes.foodDetail,
                arguments: food.id,
              ),
              onLike: viewModel.likeCurrentSwipeFood,
              onHeartTap: viewModel.toggleCurrentSwipeFoodLike,
              onContinue: viewModel.continueSwipeSession,
              onStartNew: viewModel.startNewSwipeSession,
              onMatchesTap: () async {
                await Navigator.pushNamed(
                  context,
                  AppRoutes.matchesRecommendation,
                  arguments: viewModel.matchesRecommendationRequest,
                );
                await viewModel.refreshSwipeSessionAfterMatches();
              },
            ),
          ),

        // One top overlay, stacked in a column. These used to be three
        // separate Positioned children all anchored near the top, so the
        // notice banner sat on top of the filter panel's first row and ate
        // taps meant for the Meal chips.
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.sm,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Above the rest: it is the only one asking for a decision.
              if (viewModel.mapUpdateAvailable) ...<Widget>[
                MapUpdateBanner(
                  message: viewModel.mapUpdateMessage,
                  onUpdate: viewModel.applyMapUpdate,
                  onDismiss: viewModel.dismissMapUpdate,
                  busy: viewModel.isBusy,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (viewModel.notice != null) ...<Widget>[
                _NoticeBanner(
                  message: viewModel.notice!,
                  onDismiss: viewModel.dismissNotice,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (viewModel.hasError) ...<Widget>[
                _ErrorBanner(
                  message: viewModel.errorMessage ?? 'Something went wrong.',
                  onRetry: viewModel.retry,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (viewModel.filterPanelOpen)
                MapFilterPanel(
                  labelFor: viewModel.labelFor,
                  optionsFor: viewModel.optionsFor,
                  selectionFor: viewModel.selectionFor,
                  isExpanded: viewModel.isGroupExpanded,
                  onToggleOption: viewModel.toggleFilterOption,
                  onClearGroup: viewModel.clearFilterGroup,
                  onToggleExpanded: viewModel.toggleGroupExpanded,
                ),
              if (viewModel.searchPanelOpen &&
                  viewModel.searchKeyword.isNotEmpty)
                MapSearchResultsPanel(
                  results: viewModel.searchResults,
                  searching: viewModel.searching,
                  message: viewModel.searchMessage,
                  onPlaceSelected: viewModel.selectPlace,
                  onFoodSelected: viewModel.selectSearchedFood,
                ),
            ],
          ),
        ),

        if (viewModel.selectedRegion != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RegionScoreCard(
              availability: viewModel.selectedRegion!,
              onDismiss: viewModel.dismissRegionCard,
              onExplore: () => viewModel.openRegion(viewModel.selectedRegion!),
            ),
          ),

        if (viewModel.selectedPin != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RestaurantPinSheet(
              pin: viewModel.selectedPin!,
              onDismiss: viewModel.dismissPin,
              onOpen: viewModel.openSelectedPin,
            ),
          ),

        // Busy sits at the bottom edge, clear of the top overlay column.
        if (viewModel.isBusy)
          const Positioned(
            bottom: AppSpacing.lg,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _map(DashboardViewModel viewModel) {
    // Only ever built for the detailed view - the overview is
    // `RegionHeatmapCanvas`, which paints its own ground.
    return ColoredBox(
      color: AppColors.background,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(
            viewModel.centreLatitude,
            viewModel.centreLongitude,
          ),
          initialZoom: viewModel.zoom,
          minZoom: viewModel.minimumZoom,
          maxZoom: viewModel.maximumZoom,
          // REQ102_1 - the camera can never leave Malaysia.
          cameraConstraint: CameraConstraint.containCenter(
            bounds: LatLngBounds(
              LatLng(viewModel.malaysiaSouth, viewModel.malaysiaWest),
              LatLng(viewModel.malaysiaNorth, viewModel.malaysiaEast),
            ),
          ),
          // REQ102_2 / REQ102_4 - pinch to zoom, but no rotation: a rotated
          // heatmap makes the state labels unreadable and buys nothing.
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            _mapReady = true;
            // The ViewModel usually asks for its first camera position before
            // the map is ready to move; one rebuild here replays it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          },
          onTap: (TapPosition _, LatLng point) =>
              viewModel.onMapTapped(point.latitude, point.longitude),
          // REQ102_12 / REQ102_13 - crossing the predefined zoom level here is
          // what swaps the heatmap for the detailed map, and back.
          // Deferred by a microtask: flutter_map can report a camera change from
          // inside a build, and notifying listeners there would be a setState
          // during build. The microtask runs once the frame has unwound.
          onPositionChanged: (MapCamera camera, bool _) {
            final LatLng centre = camera.center;
            final double zoom = camera.zoom;
            final LatLngBounds bounds = camera.visibleBounds;
            Future<void>.microtask(() {
              if (!mounted) return;
              viewModel.onCameraChanged(
                latitude: centre.latitude,
                longitude: centre.longitude,
                zoom: zoom,
                south: bounds.south,
                west: bounds.west,
                north: bounds.north,
                east: bounds.east,
              );
            });
          },
        ),
        children: <Widget>[
          // UC300 BF-1 - the detailed view is the real OpenStreetMap surface.
          TileLayer(
            urlTemplate: Env.osmTileUrl,
            userAgentPackageName: 'com.rasaroute.app',
          ),

          // REQ102_1 - the map covers only Malaysia. One polygon over the whole
          // world with the coastlines cut out of it, filled with the scaffold
          // cream, so the tiles only show through inside the country. Drawn
          // before the pins so it never covers one.
          if (viewModel.showCountryMask)
            PolygonLayer(
              polygons: <Polygon>[
                Polygon(
                  points: _wholeWorld,
                  holePointsList: viewModel.countryMaskOutlines
                      .map(
                        (CountryOutline outline) => outline.ring
                            .map(
                              (GeoPoint point) =>
                                  LatLng(point.latitude, point.longitude),
                            )
                            .toList(growable: false),
                      )
                      .toList(growable: false),
                  color: AppColors.background,
                  borderStrokeWidth: 0,
                ),
              ],
            ),

          // REQ102_41 - aggregated counts while the map is zoomed out. One
          // badge per grid cell, counted in Postgres: at a Malaysia-wide view
          // this is seven markers instead of twelve thousand.
          if (viewModel.clusters.isNotEmpty)
            MarkerLayer(
              markers: viewModel.clusters
                  .map(
                    (MapCluster cluster) => Marker(
                      key: ValueKey<String>(cluster.key),
                      point: LatLng(cluster.latitude, cluster.longitude),
                      width: _clusterDiameter(cluster.count),
                      height: _clusterDiameter(cluster.count),
                      child: _ClusterMarker(
                        count: cluster.count,
                        onTap: () => viewModel.zoomIntoCluster(cluster),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),

          // REQ102_32 - restaurant and submitted-landmark pins.
          MarkerLayer(
            markers: viewModel.pins
                .map(
                  (MapPin pin) => Marker(
                    point: LatLng(pin.latitude, pin.longitude),
                    width: AppSizes.mapPinSize,
                    height: AppSizes.mapPinSize,
                    child: _PinMarker(
                      pin: pin,
                      selected:
                          viewModel.selectedPin?.referenceId ==
                              pin.referenceId &&
                          viewModel.selectedPin?.kind == pin.kind,
                      onTap: () => viewModel.selectPin(pin),
                    ),
                  ),
                )
                .toList(growable: false),
          ),

          // The tourist's own position (REQ102_7), and only when that position
          // is inside Malaysia (A3) - see `showCurrentLocation`.
          if (viewModel.showCurrentLocation)
            MarkerLayer(
              markers: <Marker>[
                Marker(
                  point: LatLng(
                    viewModel.location.latitude,
                    viewModel.location.longitude,
                  ),
                  width: 22,
                  height: 22,
                  child: const _CurrentLocationDot(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A cluster badge grows with what it stands for, but slowly - a count ten
/// times larger is not a marker ten times wider, or one busy city would cover
/// the peninsula. Three sizes, chosen so the digits always fit.
double _clusterDiameter(int count) {
  if (count >= 1000) return 56;
  if (count >= 100) return 48;
  return 40;
}

/// "1,200 places here", drawn as one tappable circle.
class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.surface, width: 2),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          _label(count),
          textAlign: TextAlign.center,
          style: AppTextStyles.compactBadgeLabel.copyWith(
            color: AppColors.onPrimary,
          ),
        ),
      ),
    ),
  );

  /// Four digits do not fit on a 56pt circle, so past a thousand the count is
  /// abbreviated rather than truncated.
  static String _label(int count) {
    if (count < 1000) return '$count';
    final double thousands = count / 1000;
    return thousands >= 10
        ? '${thousands.round()}k'
        : '${thousands.toStringAsFixed(1)}k';
  }
}

/// The mask's outer ring. Latitude stops at +/-85 because that is where Web
/// Mercator does, and longitude a hair inside +/-180 so the ring cannot wrap.
final List<LatLng> _wholeWorld = <LatLng>[
  LatLng(-85, -179.9),
  LatLng(-85, 179.9),
  LatLng(85, 179.9),
  LatLng(85, -179.9),
];

/// A11 - a restaurant or submitted-landmark pin on the detailed map view
/// (REQ102_32).
///
/// Both sources use the same landmark glyph, and the **colour** is what tells
/// them apart: yellow for a landmark another tourist submitted, red for a
/// restaurant the system already knew about. One shape means the map reads as
/// one set of places; the colour answers "who put this here".
///
/// The white halo is not decoration - a yellow pin on a pale road or a red one
/// on a park needs an edge to stay legible.
class _PinMarker extends StatelessWidget {
  const _PinMarker({
    required this.pin,
    required this.selected,
    required this.onTap,
  });

  final MapPin pin;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool userSubmitted = pin.kind == MapPinKind.landmark;
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        Icons.location_on,
        size: selected ? AppSizes.mapPinSize : AppSizes.mapPinSize - 6,
        color: userSubmitted
            ? AppColors.pinUserLandmark
            : AppColors.pinSystemRestaurant,
        shadows: <Shadow>[
          // The white halo/border to make it pop.
          const Shadow(color: AppColors.surface, blurRadius: 2),
          const Shadow(color: AppColors.surface, blurRadius: 4),
          if (selected)
            const Shadow(
              color: AppColors.surface,
              blurRadius: 8,
            ),
          // The soft selection glow/ring.
          Shadow(
            color: selected ? AppColors.pinSelectedRing : AppColors.shadow,
            blurRadius: selected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.currentLocationMarker,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.surface, width: 3),
      boxShadow: const <BoxShadow>[
        BoxShadow(color: AppColors.shadow, blurRadius: 6),
      ],
    ),
  );
}

/// Presenter tool (dev builds only, Android only): opens a picker of preset
/// Malaysian spots - or a custom lat/lon typed by the tourist - and teleports
/// the OS-level GPS there, so the dashboard can be demoed "at" that location
/// without moving the device. Wired through
/// `DashboardViewModel` to `MockLocationService` (the vendored
/// `fluttermocklocation` plugin); requires Android Developer Options >
/// "Select mock location app" to point at this app.
///
/// A toggle: while a mock is live the button turns into "Stop mock", which
/// clears the OS test provider and lets the real GPS drive the map again.
class _MockGpsButton extends StatelessWidget {
  const _MockGpsButton({required this.viewModel});

  final DashboardViewModel viewModel;

  static const List<({String label, double lat, double lon})> _presets =
      <({String label, double lat, double lon})>[
        (label: 'KL', lat: 3.1390, lon: 101.6869),
        (label: 'Penang', lat: 5.4141, lon: 100.3288),
        (label: 'Kota Kinabalu', lat: 5.9804, lon: 116.0735),
        (label: 'Kuching', lat: 1.5535, lon: 110.3593),
        (label: 'Outside MY', lat: 1.3521, lon: 103.8198),
        (label: 'At sea', lat: 3.0, lon: 100.2),
      ];

  @override
  Widget build(BuildContext context) {
    final bool active = viewModel.mockGpsActive;
    return IconButton.filledTonal(
      tooltip: active ? 'Stop GPS mock (dev)' : 'Mock GPS (dev)',
      style: active
          ? IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            )
          : null,
      icon: Icon(active ? Icons.location_off : Icons.my_location),
      onPressed: active ? () => _stopMock(context) : () => _openPicker(context),
    );
  }

  Future<void> _stopMock(BuildContext context) async {
    await viewModel.stopMockGps();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('GPS mock stopped (dev)')));
  }

  Future<void> _openPicker(BuildContext context) async {
    final _MockGpsChoice? choice = await showModalBottomSheet<_MockGpsChoice>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final ({String label, double lat, double lon}) p in _presets)
                ActionChip(
                  label: Text(p.label),
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    _MockGpsChoice.preset(p.lat, p.lon),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: const Text('Custom…'),
                onPressed: () =>
                    Navigator.pop(sheetContext, const _MockGpsChoice.custom()),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    // "Custom…" closes the sheet and opens the lat/lon dialog in its place;
    // a preset is used as-is.
    final ({double lat, double lon})? custom = choice.isCustom
        ? await showDialog<({double lat, double lon})>(
            context: context,
            builder: (_) => const _CustomCoordinatesDialog(),
          )
        : (lat: choice.latitude, lon: choice.longitude);
    if (custom == null || !context.mounted) return;

    final String? error = await viewModel.setMockGps(custom.lat, custom.lon);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? 'GPS mocked (dev)')));
  }
}

/// What the mock-GPS picker sheet hands back: a preset spot, or a request to
/// type a custom coordinate (the sheet closes and a small dialog opens).
class _MockGpsChoice {
  const _MockGpsChoice.preset(this.latitude, this.longitude) : isCustom = false;

  const _MockGpsChoice.custom() : latitude = 0, longitude = 0, isCustom = true;

  final double latitude;
  final double longitude;
  final bool isCustom;
}

/// The custom-coordinate dialog behind the picker's "Custom…" chip - the only
/// way the presenter tool can jump to a spot the presets don't cover.
/// Validates ranges (latitude -90..90, longitude -180..180) before returning
/// the typed pair.
class _CustomCoordinatesDialog extends StatefulWidget {
  const _CustomCoordinatesDialog();

  @override
  State<_CustomCoordinatesDialog> createState() =>
      _CustomCoordinatesDialogState();
}

class _CustomCoordinatesDialogState extends State<_CustomCoordinatesDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, (
      lat: double.parse(_latitudeController.text.trim()),
      lon: double.parse(_longitudeController.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom GPS coordinates'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _latitudeController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 3.1390',
              ),
              validator: (String? value) {
                final double? lat = double.tryParse((value ?? '').trim());
                if (lat == null || lat < -90 || lat > 90) {
                  return 'Latitude must be a number between -90 and 90.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 101.6869',
              ),
              validator: (String? value) {
                final double? lon = double.tryParse((value ?? '').trim());
                if (lon == null || lon < -180 || lon > 180) {
                  return 'Longitude must be a number between -180 and 180.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Mock GPS')),
      ],
    );
  }
}

/// M3, and the two "showing the whole country instead" explanations.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.bannerCautionBackground,
    borderRadius: AppRadius.cardRadius,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.bannerCautionText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.bannerCautionText,
              ),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.close,
                size: 16,
                color: AppColors.bannerCautionText,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.bannerWarningBackground,
    borderRadius: AppRadius.cardRadius,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.bannerWarningText,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
