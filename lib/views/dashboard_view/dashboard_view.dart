import 'dart:math' as math;

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
import '../common_widgets/mock_gps_button.dart';
import 'widgets/discovery_layer_bar.dart';
import 'widgets/map_controls.dart';
import 'widgets/map_filter_panel.dart';
import 'widgets/map_search_bar.dart';
import 'widgets/map_search_results_panel.dart';
import 'widgets/search_history_panel.dart';
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

  /// The place a search result asked to be shown, kept after the move has
  /// landed so the map can be re-framed if the space below it changes.
  ///
  /// Null whenever nothing is being shown off - an ordinary pan, a state
  /// opened from the heatmap, or the card being dismissed - and then none of
  /// the bottom-panel arithmetic below runs at all.
  LatLng? _focusTarget;
  double _focusZoom = 0;

  /// What the bottom of the map is currently losing.
  ///
  /// Two panels can sit there and the place card is drawn **over** the
  /// Discovery Layer Bar, so what the map loses is the taller of the two, not
  /// their sum. The card's height is measured rather than assumed: it has no
  /// fixed size - the name, the "Serves:" strip and whether there is a photo
  /// all move it.
  double _pinSheetHeight = 0;
  double _swipeBarHeight = 0;

  double get _bottomInset => math.max(_pinSheetHeight, _swipeBarHeight);

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
  ///
  /// A request flagged `cameraKeepsPlaceClear` does not go to the screen
  /// centre. It is a restaurant or landmark the tourist picked out of the
  /// search results, and its card is about to open over the bottom of the map;
  /// centring it would put the pin behind the card the pin is there to
  /// introduce.
  void _applyCameraRequest(DashboardViewModel viewModel) {
    if (!_mapReady) return;
    if (viewModel.cameraRevision == _appliedCameraRevision) return;
    _appliedCameraRevision = viewModel.cameraRevision;

    final LatLng target = LatLng(
      viewModel.cameraLatitude,
      viewModel.cameraLongitude,
    );
    final double zoom = viewModel.cameraZoom;
    final bool keepClear = viewModel.cameraKeepsPlaceClear;

    if (keepClear) {
      _focusTarget = target;
      _focusZoom = zoom;
    } else {
      _focusTarget = null;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (keepClear) {
        // Reads `_focusTarget`, not the captured one: a newer request may have
        // replaced it between the frames, and the newer request wins.
        _moveFocusClearOfBottomPanel();
        return;
      }
      _mapController.move(target, zoom);
    });
  }

  /// Puts [_focusTarget] in the middle of the map the tourist can **see**,
  /// rather than the middle of the map widget.
  ///
  /// The visible band runs from the top of the map to the top of the bottom
  /// panel, so its middle sits half the panel's height above the middle of the
  /// screen - and that is exactly how far the target has to be lifted. The
  /// arithmetic is done in the projected pixel plane at the destination zoom,
  /// where lifting the target by n pixels is lowering the camera centre by n,
  /// so it stays correct at every zoom and every latitude.
  void _moveFocusClearOfBottomPanel() {
    final LatLng? target = _focusTarget;
    if (target == null || !_mapReady) return;

    final MapCamera camera = _mapController.camera;
    final double mapHeight = camera.nonRotatedSize.y;
    if (mapHeight <= 0) {
      // The map has not been measured yet. Centre it for now; the measurement
      // that follows will call back here and re-frame it.
      _mapController.move(target, _focusZoom);
      return;
    }

    double lift = _bottomInset.clamp(0.0, mapHeight) / 2;

    // Never so far that the pin climbs out of the top of the map. The
    // clearance keeps the marker and a margin of map around it on screen,
    // which is the point of moving it at all.
    final double highestLift = math.max(0, mapHeight / 2 - _focusTopClearance);
    if (lift > highestLift) lift = highestLift;

    // Below a pixel there is nothing worth correcting, and a plain move keeps
    // the centre exact.
    if (lift < 1) {
      _mapController.move(target, _focusZoom);
      return;
    }

    final math.Point<double> targetPoint = camera.project(target, _focusZoom);
    final LatLng centre = camera.unproject(
      math.Point<double>(targetPoint.x, targetPoint.y + lift),
      _focusZoom,
    );
    _mapController.move(centre, _focusZoom);
  }

  /// Keeps the two bottom-panel heights in step with what is on screen.
  ///
  /// The Discovery Layer Bar's height is known from its own state; the place
  /// card's is measured by `_MeasureHeight` as it lays out, so this only has
  /// to notice when the card has gone.
  void _syncBottomPanels(DashboardViewModel viewModel) {
    if (viewModel.selectedPin == null) {
      // The card is dismissed. Stop steering by it *before* clearing its
      // height, so its disappearance does not drag the map back.
      _focusTarget = null;
      _setPinSheetHeight(0);
    }
    _setSwipeBarHeight(
      viewModel.showSwipePanel ? _swipePanelHeight(viewModel) : 0,
    );
  }

  void _setPinSheetHeight(double height) {
    if ((height - _pinSheetHeight).abs() < 0.5) return;
    final double before = _bottomInset;
    _pinSheetHeight = height;
    _reframeIfBottomInsetChanged(before);
  }

  void _setSwipeBarHeight(double height) {
    if ((height - _swipeBarHeight).abs() < 0.5) return;
    final double before = _bottomInset;
    _swipeBarHeight = height;
    _reframeIfBottomInsetChanged(before);
  }

  /// Re-frames the focused place when the space beneath it changes - the card
  /// finishing its first layout, the Discovery Layer Bar sliding open or shut.
  ///
  /// No focus, no work: this is the whole cost of the feature during ordinary
  /// panning. Nothing here calls `setState`, because the inset is not drawn -
  /// it only tells the map controller where to sit.
  void _reframeIfBottomInsetChanged(double before) {
    if (_focusTarget == null) return;
    if ((_bottomInset - before).abs() < 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _moveFocusClearOfBottomPanel();
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
                _syncBottomPanels(viewModel);

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
        onClear: viewModel.clearSearch,
        onTap: viewModel.openSearchPanel,
        onSubmitted: viewModel.submitSearch,
        // Offered on both surfaces. The filter narrows the same food selection
        // either way - the heatmap's scores on one, the pins on the other - and
        // `applyFilter` already reloads whichever view is showing, so gating
        // it to the heatmap only hid a control that worked.
        onFilterTap: viewModel.toggleFilterPanel,
        // The *applied* count, not the draft's: this badge says what the map is
        // showing, and half-ticked chips have not reached it yet.
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
                MockGpsButton(
                  isActive: viewModel.mockGpsActive,
                  onSetMock: viewModel.setMockGps,
                  onStopMock: viewModel.stopMockGps,
                ),
              ],
            ],
          ),
        ),

        // A9 - tapping obtains a fresh GPS fix before navigation.
        if (viewModel.showQuickModeButton)
          Positioned(
            left: AppSpacing.lg,
            // Sits on the bar when there is one. There is not one while a
            // keyword is active, and the button has to drop with it rather
            // than float over empty map.
            bottom: viewModel.showSwipePanel
                ? _swipePanelHeight(viewModel) + AppSpacing.sm
                : AppSpacing.lg,
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
              if (viewModel.swipeQueueUpdateAvailable) ...<Widget>[
                MapUpdateBanner(
                  message: viewModel.swipeQueueUpdateMessage,
                  onUpdate: viewModel.applySwipeQueueUpdate,
                  onDismiss: viewModel.dismissSwipeQueueUpdate,
                  busy: viewModel.swipeLoading,
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
                  selectionCount: viewModel.draftSelectionCount,
                  onToggleOption: viewModel.toggleFilterOption,
                  onClearGroup: viewModel.clearFilterGroup,
                  onToggleExpanded: viewModel.toggleGroupExpanded,
                  onApply: viewModel.applyFilter,
                  onCancel: viewModel.cancelFilter,
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

              // REQ102_104 - the same slot, while the field is still empty.
              // `showSearchHistory` is the exact complement of the condition
              // above, so one panel hangs under the box at a time.
              if (viewModel.showSearchHistory)
                SearchHistoryPanel(
                  terms: viewModel.recentSearches,
                  onSelected: viewModel.useRecentSearch,
                  onClear: viewModel.clearSearchHistory,
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
            // Measured, not assumed: this card has no fixed height, and the
            // map needs the real number to know how far to lift the pin it is
            // about to cover.
            child: _MeasureHeight(
              onHeight: _setPinSheetHeight,
              child: RestaurantPinSheet(
                pin: viewModel.selectedPin!,
                onDismiss: viewModel.dismissPin,
                onOpen: viewModel.openSelectedPin,
              ),
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

  /// Hands one camera to the ViewModel - its centre, its zoom, its visible
  /// bounds, and the Swipe Mode rectangle read off the map geometry.
  ///
  /// Every gesture arrives here through `onPositionChanged`, and the map's
  /// opening viewport through `onMapReady` (REQ102_84). One path for both, so
  /// the ViewModel's debounce and its load revision see one kind of report and
  /// the initial fetch cannot be doubled by the gesture machinery.
  ///
  /// Deferred by a microtask: flutter_map can report a camera change from
  /// inside a build, and notifying listeners there would be a setState during
  /// build. The microtask runs once the frame has unwound.
  void _reportCamera(
    MapCamera camera,
    DashboardViewModel viewModel, {
    bool initial = false,
  }) {
    final LatLng centre = camera.center;
    final double zoom = camera.zoom;
    final LatLngBounds bounds = camera.visibleBounds;
    // Swipe Mode deliberately never moves the camera. Its fixed discovery
    // area is the unobstructed top half of this map, above the expanded card
    // panel. Convert that screen rectangle here, where the Flutter Map
    // geometry belongs, and pass only plain coordinates into the ViewModel.
    final double mapWidth = camera.nonRotatedSize.x;
    final double topHalfHeight = camera.nonRotatedSize.y / 2;
    final bool hasMeasuredMap = mapWidth > 0 && topHalfHeight > 0;
    final LatLng swipeNorthWest = hasMeasuredMap
        ? camera.pointToLatLng(const math.Point<double>(0, 0))
        : bounds.northWest;
    final LatLng swipeSouthEast = hasMeasuredMap
        ? camera.pointToLatLng(math.Point<double>(mapWidth, topHalfHeight))
        : bounds.southEast;
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
        swipeSouth: swipeSouthEast.latitude,
        swipeWest: swipeNorthWest.longitude,
        swipeNorth: swipeNorthWest.latitude,
        swipeEast: swipeSouthEast.longitude,
        initial: initial,
      );
    });
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
              if (!mounted) return;
              setState(() {});
              // REQ102_84 - the pins belong on the map from the moment it
              // exists. `onPositionChanged` reports a camera *change*, and
              // opening the map at `initialCenter` is not one, so without this
              // the ViewModel holds no bounds and the map stays bare until the
              // tourist drags it. Reported after the frame, when the map has
              // been laid out and its camera knows its own size.
              _reportCamera(_mapController.camera, viewModel, initial: true);
            });
          },
          onTap: (TapPosition _, LatLng point) =>
              viewModel.onMapTapped(point.latitude, point.longitude),
          // REQ102_12 / REQ102_13 - crossing the predefined zoom level here is
          // what swaps the heatmap for the detailed map, and back.
          onPositionChanged: (MapCamera camera, bool _) =>
              _reportCamera(camera, viewModel),
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
          //
          // **One layer, for both.** Search results and the filtered map are
          // grouped by one grid in one query, so a cell is one badge whatever
          // it holds - the count is every place in it. There were briefly two
          // layers and two grids, which is how a 100 and a 5 came to sit on top
          // of each other for places in the same street.
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
                        // How much of this badge the keyword is responsible
                        // for, which is what colours it.
                        searchCount: cluster.searchCount,
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
                      // Drawn from the same layer as everything else, marked
                      // so the tourist can tell which of these the keyword
                      // put there.
                      searchResult: viewModel.isSearchPin(pin),
                      onTap: () => viewModel.selectPin(pin),
                    ),
                  ),
                )
                .toList(growable: false),
          ),

          // The tourist's own position (REQ102_7), and only when that position
          // is inside Malaysia (A3) - see `showCurrentLocation`.
          //
          // **Drawn last, and deaf.** It has to be drawn last or a pin would
          // cover the tourist's own position; but a marker is an ordinary
          // widget in a Stack, and a filled circle drawn last is the one that
          // answers a tap. A tourist standing outside a restaurant could not
          // open it - the dot marking where they stood was in the way.
          //
          // `IgnorePointer` wraps the whole layer rather than the dot inside
          // it, so nothing this layer ever grows - an accuracy halo, a heading
          // arrow - can take a tap either. The pins underneath are hit-tested
          // exactly as though it were not there, and it stays visible.
          if (viewModel.showCurrentLocation)
            IgnorePointer(
              child: MarkerLayer(
                markers: <Marker>[
                  Marker(
                    point: LatLng(
                      viewModel.location.latitude,
                      viewModel.location.longitude,
                    ),
                    width: AppSizes.currentLocationMarkerSize,
                    height: AppSizes.currentLocationMarkerSize,
                    child: const _CurrentLocationDot(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// How much map must stay above a place the search has just flown to.
///
/// Room for the marker itself and a margin of its surroundings, so the tourist
/// can see what is around the place rather than the place alone. It only binds
/// when the bottom panel covers more than half the map - on an ordinary phone
/// the pin lands in the middle of the visible band well clear of this.
const double _focusTopClearance = 72;

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
  const _ClusterMarker({
    required this.count,
    required this.onTap,
    this.searchCount = 0,
  });

  /// Every place in this cell, the keyword's and the filter's alike.
  final int count;

  /// How many of [count] the keyword is responsible for.
  ///
  /// Three looks, not two, because a cell is not one thing or the other:
  ///
  ///  * **none** - the filtered map's own badge, in the primary colour;
  ///  * **all** - everything here answers the keyword, so the badge is filled
  ///    in the search colour;
  ///  * **some** - filled as the map's, ringed in the search colour. A mixed
  ///    cell is exactly the case a second layer used to draw as two badges
  ///    fighting for the same pixel, and pretending it is wholly one or the
  ///    other would be the same lie in one marker instead of two.
  final int searchCount;

  bool get _hasSearch => searchCount > 0;
  bool get _allSearch => searchCount >= count;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _allSearch ? AppColors.clusterSearchFill : AppColors.primary,
        border: Border.fromBorderSide(
          BorderSide(
            // A mixed cell keeps the map's fill and takes the search colour as
            // its edge, so it reads as "some of these" at a glance.
            color: _hasSearch && !_allSearch
                ? AppColors.clusterSearchFill
                : AppColors.surface,
            width: _hasSearch && !_allSearch ? 3 : 2,
          ),
        ),
        boxShadow: const <BoxShadow>[
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
    this.searchResult = false,
  });

  final MapPin pin;
  final bool selected;

  /// Whether the current keyword is what put this marker on the map.
  ///
  /// Marked with a ring rather than a colour of its own: the two pin colours
  /// say where a place came from, and a search result is still a restaurant or
  /// still somebody's landmark.
  final bool searchResult;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool userSubmitted = pin.kind == MapPinKind.landmark;
    final Widget marker = Icon(
      Icons.location_on,
      size: selected || searchResult
          ? AppSizes.mapPinSize
          : AppSizes.mapPinSize - 6,
      color: userSubmitted
          ? AppColors.pinUserLandmark
          : AppColors.pinSystemRestaurant,
      shadows: <Shadow>[
        const Shadow(color: AppColors.surface, blurRadius: 3),
        Shadow(
          color: selected ? AppColors.pinSelectedRing : AppColors.surface,
          blurRadius: selected ? 6 : 4,
        ),
      ],
    );

    return GestureDetector(
      // The whole marker box, not just the glyph the icon happens to paint.
      // `deferToChild` (the default) made the tap target the icon's own text
      // box, a few points inside a marker that is already under the 48pt
      // minimum - so a tap that looked like it landed on the pin missed it.
      // This matters most beside the current-location marker, where the
      // tourist is aiming at a pin they can only half see.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: searchResult
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.pinSearchHalo,
                border: Border.all(color: AppColors.pinSearchRing, width: 2),
              ),
              child: marker,
            )
          : marker,
    );
  }
}

/// REQ102_7 - where the tourist is standing, on the detailed map.
///
/// Deliberately small. It is drawn over the pins, so every point of it is a
/// point of some restaurant the tourist cannot see; 16pt across is enough to
/// read as a position fix and leaves most of a 36pt pin showing around it.
/// The overview draws the same idea as a ring for the same reason - see
/// `RegionHeatmapCanvas._paintCurrentLocation`.
///
/// It takes no taps: the layer that holds it is wrapped in an `IgnorePointer`.
/// Reports its child's height after every layout.
///
/// The place card is as tall as its contents make it - the name, the "Serves:"
/// strip, whether the place has a photo - so the map cannot be told in advance
/// how much of itself it is about to lose. This measures the real thing and
/// hands the number back, which is also what lets the map re-frame itself when
/// the card grows or shrinks.
class _MeasureHeight extends StatefulWidget {
  const _MeasureHeight({required this.onHeight, required this.child});

  final ValueChanged<double> onHeight;
  final Widget child;

  @override
  State<_MeasureHeight> createState() => _MeasureHeightState();
}

class _MeasureHeightState extends State<_MeasureHeight> {
  @override
  Widget build(BuildContext context) {
    // After the frame, not during it: nothing has a height until this subtree
    // has been laid out. The listener compares before it acts, so a rebuild
    // that changes nothing costs one comparison and stops there - there is no
    // measure/rebuild loop to fall into.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderObject? object = context.findRenderObject();
      if (object is RenderBox && object.hasSize) {
        widget.onHeight(object.size.height);
      }
    });
    return widget.child;
  }
}

class _CurrentLocationDot extends StatelessWidget {
  const _CurrentLocationDot();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: AppSizes.currentLocationDot + AppSizes.currentLocationRing * 2,
      height: AppSizes.currentLocationDot + AppSizes.currentLocationRing * 2,
      decoration: BoxDecoration(
        color: AppColors.currentLocationMarker,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.surface,
          width: AppSizes.currentLocationRing,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 6),
        ],
      ),
    ),
  );
}

/// M3, and the two "showing the whole country instead" explanations.
/// REQ102_41 - how much of the viewport's answer is on screen.
///
/// Deliberately quiet: it reports a limit, it does not ask for anything. The
/// optional [subtitle] carries the heatmap's own count for the state under the
/// map, so the number of pins can be read against the state total rather than
/// mistaken for it.
class _PinCoverageChip extends StatelessWidget {
  const _PinCoverageChip({required this.message, this.subtitle});

  final String message;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Align(
    child: Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.place_outlined,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  message,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textDisabled,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

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
