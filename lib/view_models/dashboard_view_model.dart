import 'dart:async';

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/exploration_filter.dart';
import '../domain_model/exploration_search.dart';
import '../domain_model/food_distribution.dart';
import '../domain_model/local_food.dart';
import '../domain_model/map.dart';
import '../domain_model/region.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import '../model/data_models/location_data_model.dart';

/// Which of the two dashboard maps is showing (REQ102_12, REQ102_13).
enum DashboardMapMode { heatmap, detailed }

/// ViewModel for `DashboardView` - REQ102, the Local Food Dashboard &
/// Regional Exploration Module, following UC300.

class DashboardViewModel extends BaseViewModel {
  DashboardViewModel() {
    _live.add(this);
  }

  // ===========================================================================
  // Where the tourist is - pushed in, never polled
  // ===========================================================================
  //
  //   LocationMonitor -> CurrentLocationFacade.publish()
  //                   -> DashboardViewModel.onCurrentLocationChanged()  [here]
  //
  // The fix lives in a **static** field rather than an instance one, so it
  // survives this ViewModel being disposed and rebuilt. A tourist who switches
  // to another tab and comes back sees their position at once instead of a
  // blank map waiting on the next GPS tick.

  /// Every live instance, so the static entry point can reach them. Added in
  /// the constructor, removed in `dispose` - an instance that is not removed
  /// would be notified forever.
  static final Set<DashboardViewModel> _live = <DashboardViewModel>{};

  static LocationDataModel _sharedLocation = LocationDataModel.unknown;

  /// The most recent GPS fix, shared by every instance of this ViewModel.
  static LocationDataModel get sharedLocation => _sharedLocation;

  /// **Called by `CurrentLocationFacade`, which `LocationMonitor` calls.**
  /// Nothing else should call it.
  static void onCurrentLocationChanged(LocationDataModel location) {
    _sharedLocation = location;
    for (final DashboardViewModel viewModel
        in Set<DashboardViewModel>.of(_live)) {
      viewModel._onLocationPushed();
    }
  }

  final DiscoveryLogicFacade discoveryLogic = DiscoveryLogicFacade();

  // ===========================================================================
  // Map view + camera
  // ===========================================================================

  DashboardMapMode _mode = DashboardMapMode.heatmap;
  DashboardMapMode get mode => _mode;
  bool get isHeatmapView => _mode == DashboardMapMode.heatmap;
  bool get isDetailedView => _mode == DashboardMapMode.detailed;

  double _zoom = DiscoveryLogicFacade.malaysiaOverviewZoom;
  double get zoom => _zoom;

  double _centreLatitude = DiscoveryLogicFacade.malaysiaCentreLatitude;
  double _centreLongitude = DiscoveryLogicFacade.malaysiaCentreLongitude;
  double get centreLatitude => _centreLatitude;
  double get centreLongitude => _centreLongitude;

  // The camera is a *request*, not a fact: the ViewModel asks for a position,
  // the View's map controller applies it and reports back through
  // [onCameraChanged]. [cameraRevision] increments on every request so the
  // View can tell a new instruction from a rebuild.
  double _cameraLatitude = DiscoveryLogicFacade.malaysiaCentreLatitude;
  double _cameraLongitude = DiscoveryLogicFacade.malaysiaCentreLongitude;
  double _cameraZoom = DiscoveryLogicFacade.malaysiaOverviewZoom;
  int _cameraRevision = 0;

  double get cameraLatitude => _cameraLatitude;
  double get cameraLongitude => _cameraLongitude;
  double get cameraZoom => _cameraZoom;
  int get cameraRevision => _cameraRevision;

  // ===========================================================================
  // The heatmap illustration
  // ===========================================================================
  //
  // The overview is painted, not a slippy map (see `RegionHeatmapCanvas` for
  // why), so its zoom is a canvas scale factor the View reports back.

  int _heatmapResetToken = 0;

  /// Bumped when the dashboard returns to the overview - the View drops the
  /// canvas back to its resting scale.
  int get heatmapResetToken => _heatmapResetToken;

  double _heatmapScale = 1;
  double get heatmapScale => _heatmapScale;

  /// REQ102_12 - "the predefined zoom level", as a canvas scale factor.
  double get heatmapDetailScale => DiscoveryLogicFacade.heatmapDetailScale;

  /// Reported by the canvas so the "+" / "-" buttons enable correctly.
  void onHeatmapScaleChanged(double scale) {
    if ((_heatmapScale - scale).abs() < 0.001) return;
    _heatmapScale = scale;
    safeNotifyListeners();
  }

  /// REQ102_12 - pinched past the predefined level. The state under the middle
  /// of the screen is the one the detailed map view opens on (UC300 BF-5).
  void onHeatmapZoomedInto(RegionAvailability availability) {
    if (isDetailedView) return;
    openRegion(availability);
  }

  // ===========================================================================
  // Heatmap + pins
  // ===========================================================================

  FoodDistribution _distribution = FoodDistribution.empty;
  FoodDistribution get distribution => _distribution;
  List<RegionAvailability> get regionScores => _distribution.regions;

  List<MapPin> _pins = const <MapPin>[];
  List<MapPin> get pins => _pins;

  List<CountryOutline> _countryOutlines = const <CountryOutline>[];

  /// REQ102_1 - the tight coastline the painted overview clips its blur to.
  List<CountryOutline> get countryOutlines => _countryOutlines;

  List<CountryOutline> _countryMaskOutlines = const <CountryOutline>[];

  /// REQ102_1 - the generous rings the detailed map cuts out of its mask.
  List<CountryOutline> get countryMaskOutlines => _countryMaskOutlines;

  /// REQ102_1 - whether to hide everything that is not Malaysia.
  ///
  /// Only in the detailed view (the overview paints Malaysia and nothing else
  /// anyway), and only while zoomed out far enough that the coarse outlines
  /// still look like a coastline.
  bool get showCountryMask =>
      isDetailedView &&
      _countryMaskOutlines.isNotEmpty &&
      _zoom < DiscoveryLogicFacade.countryMaskMaxZoom;

  RegionAvailability? _selectedRegion;
  RegionAvailability? get selectedRegion => _selectedRegion;

  MapPin? _selectedPin;
  MapPin? get selectedPin => _selectedPin;

  // ===========================================================================
  // Filters (REQ102_23 - REQ102_29)
  // ===========================================================================

  ExplorationFilter _filter = ExplorationFilter.none;
  ExplorationFilter get filter => _filter;

  bool _filterPanelOpen = false;
  bool get filterPanelOpen => _filterPanelOpen;

  final Set<ExplorationFilterGroup> _expandedGroups = <ExplorationFilterGroup>{};
  bool isGroupExpanded(ExplorationFilterGroup group) =>
      _expandedGroups.contains(group);

  List<String> optionsFor(ExplorationFilterGroup group) =>
      discoveryLogic.filterOptions(group);

  /// The one option chosen in [group], or null for "All".
  String? selectionFor(ExplorationFilterGroup group) => switch (group) {
    ExplorationFilterGroup.meal => _filter.meal,
    ExplorationFilterGroup.category => _filter.category,
    ExplorationFilterGroup.taste => _filter.taste,
    ExplorationFilterGroup.type => _filter.type,
  };

  /// The pill that opens each filter row in the dropdown panel.
  String labelFor(ExplorationFilterGroup group) =>
      discoveryLogic.filterLabel(group);

  // ===========================================================================
  // Search (A8)
  // ===========================================================================

  String _searchKeyword = '';
  String get searchKeyword => _searchKeyword;

  bool _searchPanelOpen = false;
  bool get searchPanelOpen => _searchPanelOpen;

  ExplorationSearchResults _searchResults = ExplorationSearchResults.empty;
  ExplorationSearchResults get searchResults => _searchResults;

  bool _searching = false;
  bool get searching => _searching;

  /// A8.2 / M2 - shown under the search field when nothing matched.
  String? _searchMessage;
  String? get searchMessage => _searchMessage;

  static const String noResultMessage =
      'No location or local food matches your input. Please try again.';

  static const String notInMalaysiaMessage =
      'You are not in Malaysia, you are not allowed to use Quick Mode.';

  /// The dish the map is currently narrowed to (REQ102_32, REQ102_33).
  ///
  /// **This is the variable REQ103 drives.** Whatever sits here is the only
  /// food the heatmap scores and the only food whose restaurants get pins;
  /// null means "all local food". Two things set it today - a Local Food
  /// search result, and the Target Frame.
  ///
  /// @param selectedFood (swipe mode) - set it through
  ///        [showFoodInTargetFrame], never by assigning here.
  LocalFood? _selectedFood;
  LocalFood? get selectedFood => _selectedFood;

  // ===========================================================================
  // Location (REQ102_6 - REQ102_9, REQ102_14)
  // ===========================================================================

  /// Reads the shared fix, so a freshly built ViewModel starts with whatever
  /// the monitor last published rather than `unknown`.
  LocationDataModel get location => _sharedLocation;

  bool _locationPermissionGranted = false;
  bool get locationPermissionGranted => _locationPermissionGranted;

  bool _locationInMalaysia = false;
  bool get locationInMalaysia => _locationInMalaysia;

  bool _locating = false;
  bool get locating => _locating;

  /// A one-shot banner - M3 for Quick Mode outside Malaysia, or the
  /// explanation shown when GPS is denied and the overview is used instead.
  String? _notice;
  String? get notice => _notice;

  // ===========================================================================
  // Derived UI state
  // ===========================================================================

  /// REQ102_9 - only once a fix inside Malaysia has been obtained.
  bool get showFindMeButton => _locationInMalaysia && _sharedLocation.isKnown;

  bool _swipePanelExpanded = false;

  /// REQ103_1 calls the Discovery Layer Bar "a sliding bottom-sheet", so it has
  /// a collapsed peek and an expanded state. It starts collapsed: expanded it
  /// is 236pt, which is 40% of the map on a 390x844 phone, and until REQ103
  /// fills it there is nothing in there worth that much screen.
  bool get swipePanelExpanded => _swipePanelExpanded;

  void toggleSwipePanel() {
    _swipePanelExpanded = !_swipePanelExpanded;
    safeNotifyListeners();
  }

  /// REQ102_10 - the Discovery Layer Bar appears with the detailed map view.
  bool get showSwipePanel => isDetailedView;

  /// REQ102_11 - Quick Mode needs the detailed view *and* a fix in Malaysia.
  bool get showQuickModeButton => isDetailedView && _locationInMalaysia;

  // The map widget needs the same limits the ViewModel clamps against. It
  // reads them from here, so no widget imports a facade or a logic class.
  double get minimumZoom => DiscoveryLogicFacade.minimumZoom;
  double get maximumZoom => DiscoveryLogicFacade.maximumZoom;
  double get malaysiaSouth => DiscoveryLogicFacade.malaysiaSouth;
  double get malaysiaWest => DiscoveryLogicFacade.malaysiaWest;
  double get malaysiaNorth => DiscoveryLogicFacade.malaysiaNorth;
  double get malaysiaEast => DiscoveryLogicFacade.malaysiaEast;

  bool get canZoomIn => isHeatmapView
      ? _heatmapScale < 8
      : _zoom < DiscoveryLogicFacade.maximumZoom;

  bool get canZoomOut => isHeatmapView
      ? _heatmapScale > 1.01
      : _zoom > DiscoveryLogicFacade.minimumZoom;

  /// Title line under the search bar in the detailed view.
  String get contextLabel {
    if (_selectedFood != null) return 'Showing ${_selectedFood!.name}';
    if (_filter.selectionCount > 0) {
      return '${_filter.selectionCount} filter'
          '${_filter.selectionCount == 1 ? '' : 's'} applied';
    }
    return 'All local food';
  }

  // ===========================================================================
  // Lifecycle
  // ===========================================================================

  @override
  Future<void> onInit() async {
    await _loadCountryOutlines();
    await _loadHeatmap();
    await locateTourist();
  }

  /// Constant reference data, so a failure here must not take the dashboard
  /// down with it - the map simply goes unmasked.
  Future<void> _loadCountryOutlines() async {
    try {
      _countryOutlines = await discoveryLogic.countryOutlines();
      _countryMaskOutlines = await discoveryLogic.countryMaskOutlines();
    } catch (_) {
      _countryOutlines = const <CountryOutline>[];
      _countryMaskOutlines = const <CountryOutline>[];
    }
  }

  /// One instance's reaction to a pushed fix. A background fix should update
  /// the Find Me and Quick Mode affordances, but must never yank the camera
  /// away from wherever the tourist panned to.
  void _onLocationPushed() {
    safeNotifyListeners();
    _refreshWithinMalaysia();
  }

  @override
  void dispose() {
    _pinRefreshTimer?.cancel();
    _live.remove(this);
    super.dispose();
  }

  // ===========================================================================
  // Location commands
  // ===========================================================================

  /// UC300 BF-3 / A1 / A2 / A3, and A14 "Find Me".
  ///
  /// Asks for permission, takes a fix, and either centres on it (REQ102_8) or
  /// falls back to the Malaysia overview (REQ102_14). A refusal is a normal
  /// outcome, not an error - the dashboard still works, it just shows the
  /// whole country.
  Future<void> locateTourist() async {
    _locating = true;
    safeNotifyListeners();
    try {
      _locationPermissionGranted =
          await discoveryLogic.ensureLocationPermission();

      if (!_locationPermissionGranted) {
        _locationInMalaysia = false;
        _notice =
            'Location permission is off, so the map is showing all of '
            'Malaysia. Turn it on to centre on where you are.';
        _showMalaysiaOverview();
        return;
      }

      final LocationDataModel fix = await discoveryLogic.currentLocation();
      _sharedLocation = fix;

      if (!fix.isKnown) {
        _locationInMalaysia = false;
        _showMalaysiaOverview();
        return;
      }

      _locationInMalaysia = await discoveryLogic.isWithinMalaysia(
        fix.latitude,
        fix.longitude,
      );

      if (!_locationInMalaysia) {
        // A3 - outside Malaysia, so the overview is all the app can offer.
        _notice =
            'You are outside Malaysia, so the map is showing the whole '
            'country.';
        _showMalaysiaOverview();
        return;
      }

      _requestCamera(
        fix.latitude,
        fix.longitude,
        DiscoveryLogicFacade.currentLocationZoom,
      );
    } catch (error, stackTrace) {
      setError(error, stackTrace);
    } finally {
      _locating = false;
      safeNotifyListeners();
    }
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    safeNotifyListeners();
  }

  // ===========================================================================
  // Camera commands
  // ===========================================================================

  /// REQ102_3 - the "+" button.
  void zoomIn() => _requestCamera(
    _centreLatitude,
    _centreLongitude,
    _clampZoom(_zoom + DiscoveryLogicFacade.zoomStep),
  );

  /// REQ102_5 - the "-" button.
  void zoomOut() => _requestCamera(
    _centreLatitude,
    _centreLongitude,
    _clampZoom(_zoom - DiscoveryLogicFacade.zoomStep),
  );

  /// Reported by the View after any camera movement, including the pinch
  /// gestures of REQ102_2 and REQ102_4.
  ///
  /// This is where REQ102_12 and REQ102_13 happen: crossing
  /// `DiscoveryLogicFacade.detailedViewZoom` in either direction swaps the two
  /// map views, and each view loads the data it needs.
  void onCameraChanged({
    required double latitude,
    required double longitude,
    required double zoom,
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    final bool previousCanZoomIn = canZoomIn;
    final bool previousCanZoomOut = canZoomOut;

    _centreLatitude = latitude;
    _centreLongitude = longitude;
    _zoom = zoom;
    _viewportSouth = south;
    _viewportWest = west;
    _viewportNorth = north;
    _viewportEast = east;

    final DashboardMapMode next = zoom >= DiscoveryLogicFacade.detailedViewZoom
        ? DashboardMapMode.detailed
        : DashboardMapMode.heatmap;

    if (next != _mode) {
      _mode = next;
      _selectedRegion = null;
      _selectedPin = null;
      if (next == DashboardMapMode.heatmap) _heatmapResetToken++;
      safeNotifyListeners();
      if (_mode == DashboardMapMode.detailed) {
        _loadPins();
      } else {
        _loadHeatmap();
      }
      return;
    }

    // This fires on every frame of a pinch or a drag, so notify only when
    // something the screen actually shows has changed - otherwise the whole
    // dashboard rebuilds sixty times a second for nothing.
    final bool zoomLimitsChanged =
        canZoomIn != previousCanZoomIn || canZoomOut != previousCanZoomOut;
    if (zoomLimitsChanged) safeNotifyListeners();

    // Any camera move in the detailed view can change which pins belong on
    // screen - zooming in as much as panning, because the pins are fetched for
    // the visible bounds. Debounced rather than gated on distance: a pinch
    // never moves the centre, so a distance gate meant zooming never refreshed
    // at all.
    if (_mode == DashboardMapMode.detailed) _schedulePinRefresh();
  }

  /// Coalesces the flood of camera events a single gesture produces into one
  /// fetch, fired shortly after the map settles.
  void _schedulePinRefresh() {
    _pinRefreshTimer?.cancel();
    _pinRefreshTimer = Timer(_pinRefreshDelay, () {
      if (_mode != DashboardMapMode.detailed) return;
      if (!_viewportChangedSinceLastPinLoad()) return;
      _loadPins();
    });
  }

  /// A2-5 / A6-6 - the tourist taps a state on the heatmap.
  void selectRegion(RegionAvailability region) {
    _selectedRegion = region;
    safeNotifyListeners();
  }

  /// A2-6 - centre and zoom the selected state, which crosses the threshold
  /// and therefore opens the detailed map view (UC300 BF-5).
  void openRegion(RegionAvailability availability) {
    final Region region = availability.region;
    _selectedRegion = null;
    _requestCamera(
      region.centreLatitude,
      region.centreLongitude,
      region.defaultZoom,
    );
  }

  void dismissRegionCard() {
    if (_selectedRegion == null) return;
    _selectedRegion = null;
    safeNotifyListeners();
  }

  // ===========================================================================
  // Pin selection (A11)
  // ===========================================================================

  void selectPin(MapPin pin) {
    _selectedPin = pin;
    safeNotifyListeners();
  }

  /// A11.1 - tap the map outside the overlay, or swipe it down.
  void dismissPin() {
    if (_selectedPin == null) return;
    _selectedPin = null;
    safeNotifyListeners();
  }

  /// A11-4 - open the full Restaurant Details page.
  void openSelectedPin() {
    final MapPin? pin = _selectedPin;
    if (pin == null) return;
    AppNavigator.push(
      pin.kind == MapPinKind.landmark
          ? AppRoutes.landmarkDetail
          : AppRoutes.restaurantDetail,
    );
  }

  // ===========================================================================
  // Quick Mode (A9, REQ102_11)
  // ===========================================================================

  void openQuickMode() {
    if (!_locationInMalaysia) {
      // A9.3 / M3.
      _notice = notInMalaysiaMessage;
      safeNotifyListeners();
      return;
    }
    AppNavigator.push(AppRoutes.restaurantRecommendation);
  }

  // ===========================================================================
  // Filters (A7)
  // ===========================================================================

  void toggleFilterPanel() {
    _filterPanelOpen = !_filterPanelOpen;
    safeNotifyListeners();
  }

  void toggleGroupExpanded(ExplorationFilterGroup group) {
    if (!_expandedGroups.remove(group)) _expandedGroups.add(group);
    safeNotifyListeners();
  }

  /// A7-3 - tick or untick one option, then recalculate (REQ102_28) and
  /// redraw (REQ102_29).
   /// A7-3 - choose one option in a group, then recalculate (REQ102_28) and
  /// redraw (REQ102_29).
  ///
  /// One option per group: picking a different one replaces what was there,
  /// and picking the one already chosen clears the group back to "All".
  void toggleFilterOption(ExplorationFilterGroup group, String option) {
    final String? current = selectionFor(group);
    _applyFilter(group, current == option ? null : option);
  }

  /// The "All" chip at the head of a filter row.
  void clearFilterGroup(ExplorationFilterGroup group) {
    if (selectionFor(group) == null) return;
    _applyFilter(group, null);
  }

  void _applyFilter(ExplorationFilterGroup group, String? option) {
    // Built field by field rather than through a copyWith, because copyWith
    // cannot tell "leave this alone" from "clear this to null".
    _filter = ExplorationFilter(
      meal: group == ExplorationFilterGroup.meal ? option : _filter.meal,
      category: group == ExplorationFilterGroup.category
          ? option
          : _filter.category,
      taste: group == ExplorationFilterGroup.taste ? option : _filter.taste,
      type: group == ExplorationFilterGroup.type ? option : _filter.type,
    );
    safeNotifyListeners();
    _reloadActiveView();
  }

  // ===========================================================================
  // Search (A8)
  // ===========================================================================

  void openSearchPanel() {
    _searchPanelOpen = true;
    safeNotifyListeners();
  }

  /// A8-1 / A8-2 / A8-3 - one keyword, matched against locations and food.
  Future<void> updateSearchKeyword(String keyword) async {
    _searchKeyword = keyword;
    _searchMessage = null;

    if (keyword.trim().isEmpty) {
      _searchResults = ExplorationSearchResults.empty;
      _searching = false;
      safeNotifyListeners();
      return;
    }

    _searchPanelOpen = true;
    _searching = true;
    safeNotifyListeners();

    try {
      final ExplorationSearchResults results = await discoveryLogic
          .searchExploration(keyword);
      // A late reply for a keyword the tourist has already changed must not
      // overwrite the current one.
      if (results.keyword != _searchKeyword.trim()) return;

      _searchResults = results;
      // A8.2 - no location entry and no local food entry matched.
      _searchMessage = results.places.isEmpty && results.foods.isEmpty
          ? noResultMessage
          : null;
    } catch (error, stackTrace) {
      setError(error, stackTrace);
    } finally {
      _searching = false;
      safeNotifyListeners();
    }
  }

  /// A8-4 / REQ102_22 - centre and zoom on the chosen state, city or location.
  void selectPlace(PlaceSuggestion place) {
    _searchPanelOpen = false;
    _searchKeyword = place.name;
    _searchResults = ExplorationSearchResults.empty;
    _searchMessage = null;
    _requestCamera(place.latitude, place.longitude, place.zoom);
  }

  /// A8.1 - the tourist picked a Local Food result. The heatmap is rebuilt
  /// around that one dish (REQ102_33) and, once the map is zoomed in, only its
  /// restaurants are pinned (REQ102_32).
  ///
  /// Search-flavoured: it also fills the search field and closes the result
  /// list. Swipe Mode wants [showFoodInTargetFrame] instead.
  ///
  /// @param food (search) - the Local Food row the tourist tapped.
  void selectSearchedFood(LocalFood food) {
    _selectedFood = food;
    _searchPanelOpen = false;
    _searchKeyword = food.name;
    _searchResults = ExplorationSearchResults.empty;
    _searchMessage = null;
    safeNotifyListeners();
    _reloadActiveView();
  }

  // ===========================================================================
  // REQ103 hand-off - the Target Frame drives the map
  // ===========================================================================

  /// **REQ103_8 - call this when a food card comes to rest in the Target
  /// Frame.** This is the one entry point Swipe Mode needs; everything else on
  /// the dashboard follows from it.
  ///
  /// Passing a food narrows the map to it: the heatmap is rescored for that one
  /// dish (REQ102_33) and, in the detailed view, only the restaurants and
  /// landmarks serving it are pinned (REQ102_32). Passing null puts the map
  /// back to all local food - do that when the deck empties or the tourist
  /// leaves Swipe Mode.
  ///
  /// Unlike [selectSearchedFood] this leaves the search field and the camera
  /// alone. A card sliding into the frame is not a search, and the map must not
  /// jump while the tourist is swiping.
  ///
  /// @param food (swipe mode) - the `LocalFood` currently resting in the
  ///        Target Frame, or null for none. Its `id` is what travels down to
  ///        `DiscoveryLogicFacade.mapPins(localFoodId:)` and
  ///        `foodDistribution(localFoodId:)`.
  void showFoodInTargetFrame(LocalFood? food) {
    if (_selectedFood?.id == food?.id) return;
    _selectedFood = food;
    safeNotifyListeners();
    _reloadActiveView();
  }

  /// A8.3 - clear the keyword and put the map back the way it was.
  void clearSearch() {
    final bool hadFood = _selectedFood != null;
    _searchKeyword = '';
    _searchResults = ExplorationSearchResults.empty;
    _searchMessage = null;
    _searchPanelOpen = false;
    _selectedFood = null;
    safeNotifyListeners();
    if (hadFood) _reloadActiveView();
  }

  void closeSearchPanel() {
    if (!_searchPanelOpen) return;
    _searchPanelOpen = false;
    safeNotifyListeners();
  }

  // ===========================================================================
  // Map taps
  // ===========================================================================

  /// A2-5 - the tourist taps a state on the heatmap, or taps empty map in the
  /// detailed view to dismiss whatever is open (A11.1).
  Future<void> onMapTapped(double latitude, double longitude) async {
    if (_searchPanelOpen) closeSearchPanel();
    if (_filterPanelOpen) {
      _filterPanelOpen = false;
      safeNotifyListeners();
    }

    if (isDetailedView) {
      dismissPin();
      return;
    }

    final Region? region = await discoveryLogic.regionAt(latitude, longitude);
    if (region == null) {
      dismissRegionCard();
      return;
    }
    for (final RegionAvailability availability in _distribution.regions) {
      if (availability.region.code == region.code) {
        selectRegion(availability);
        return;
      }
    }
  }

  /// REQ103_14 - the Matches count on the Discovery Layer Bar. Always zero
  /// until the swipe deck lands with REQ103; the badge exists now because
  /// REQ102_10 puts the panel on screen.
  int get matchesCount => 0;

  // ===========================================================================
  // Retry
  // ===========================================================================

  Future<void> retry() async {
    clearError();
    await _reloadActiveView();
  }

  // ===========================================================================
  // Internals
  // ===========================================================================

  double? _viewportSouth;
  double? _viewportWest;
  double? _viewportNorth;
  double? _viewportEast;

  double? _lastPinLatitude;
  double? _lastPinLongitude;
  double? _lastPinZoom;

  Timer? _pinRefreshTimer;

  /// How long the map has to sit still before the pins are refetched. Short
  /// enough to feel immediate, long enough that one pinch is one query.
  static const Duration _pinRefreshDelay = Duration(milliseconds: 250);

  /// Degrees of travel that justify refetching the pins for a new viewport.
  static const double _pinRefreshDelta = 0.05;

  /// Zoom change that justifies the same. A tenth of a level is below what
  /// anyone can pinch deliberately, so in practice any real zoom refetches.
  static const double _pinRefreshZoomDelta = 0.1;

  /// What a filter change or a food search triggers: the previous answer is
  /// stale, so the pins go before the new query runs.
  Future<void> _reloadActiveView() =>
      isHeatmapView ? _loadHeatmap() : _loadPins(clearFirst: true);

  Future<void> _loadHeatmap() => runGuarded(() async {
    // Leaving the detailed view invalidates its pins.
    if (_pins.isNotEmpty) {
      _pins = const <MapPin>[];
      safeNotifyListeners();
    }
    _distribution = await discoveryLogic.foodDistribution(
      filter: _filter,
      localFoodId: _selectedFood?.id,
    );
  }, silent: _distribution.regions.isNotEmpty);

  /// [clearFirst] wipes the pins before the query rather than swapping them
  /// when it returns.
  ///
  /// Only a filter change or a food search does that - there the old pins are
  /// answering a question the tourist has already moved on from, so leaving
  /// them up reads as the map ignoring you. Panning and zooming keep their
  /// pins on screen until the new set arrives, because those pins are still
  /// the right answer; blanking them every camera nudge just made the map
  /// flicker. Either way the camera is untouched.
  Future<void> _loadPins({bool clearFirst = false}) => runGuarded(() async {
    if (clearFirst && _pins.isNotEmpty) {
      _pins = const <MapPin>[];
      safeNotifyListeners();
    }

    _lastPinLatitude = _centreLatitude;
    _lastPinLongitude = _centreLongitude;
    _lastPinZoom = _zoom;
    _pins = await discoveryLogic.mapPins(
      filter: _filter,
      localFoodId: _selectedFood?.id,
      south: _viewportSouth,
      west: _viewportWest,
      north: _viewportNorth,
      east: _viewportEast,
      fromLatitude: _sharedLocation.isKnown ? _sharedLocation.latitude : null,
      fromLongitude: _sharedLocation.isKnown ? _sharedLocation.longitude : null,
    );
  }, silent: true);

  /// Has the viewport moved or scaled enough that the pins on screen could
  /// differ from the ones already fetched?
  bool _viewportChangedSinceLastPinLoad() {
    final double? lastLatitude = _lastPinLatitude;
    final double? lastLongitude = _lastPinLongitude;
    final double? lastZoom = _lastPinZoom;
    if (lastLatitude == null || lastLongitude == null || lastZoom == null) {
      return true;
    }
    return (lastLatitude - _centreLatitude).abs() > _pinRefreshDelta ||
        (lastLongitude - _centreLongitude).abs() > _pinRefreshDelta ||
        (lastZoom - _zoom).abs() > _pinRefreshZoomDelta;
  }

  /// REQ102_14 - the whole-country fallback.
  void _showMalaysiaOverview() => _requestCamera(
    DiscoveryLogicFacade.malaysiaCentreLatitude,
    DiscoveryLogicFacade.malaysiaCentreLongitude,
    DiscoveryLogicFacade.malaysiaOverviewZoom,
  );

  /// Every explicit navigation goes through here: Find Me, a search result, a
  /// state opened from the heatmap, the overview fallback.
  ///
  /// It is also the one place an explicit move decides which of the two views
  /// is showing. The heatmap is a painted illustration, not the slippy map, so
  /// it cannot report its own zoom back the way `onCameraChanged` does -
  /// asking for a camera above the predefined level *is* the switch to the
  /// detailed view (REQ102_12), and asking for one below it is the way back
  /// (REQ102_13).
  void _requestCamera(double latitude, double longitude, double zoom) {
    _cameraLatitude = latitude;
    _cameraLongitude = longitude;
    _cameraZoom = _clampZoom(zoom);
    _cameraRevision++;

    _centreLatitude = latitude;
    _centreLongitude = longitude;
    _zoom = _cameraZoom;

    final DashboardMapMode next =
        _cameraZoom >= DiscoveryLogicFacade.detailedViewZoom
        ? DashboardMapMode.detailed
        : DashboardMapMode.heatmap;
    final bool changed = next != _mode;
    _mode = next;

    if (changed) {
      _selectedRegion = null;
      _selectedPin = null;
      // Put the illustration back to its resting scale, so returning to the
      // overview never lands on a half-pinched canvas.
      if (next == DashboardMapMode.heatmap) _heatmapResetToken++;
    }

    safeNotifyListeners();

    if (changed) {
      if (next == DashboardMapMode.detailed) {
        _loadPins();
      } else {
        _loadHeatmap();
      }
    }
  }

  Future<void> _refreshWithinMalaysia() async {
    if (!_sharedLocation.isKnown) return;
    final bool inside = await discoveryLogic.isWithinMalaysia(
      _sharedLocation.latitude,
      _sharedLocation.longitude,
    );
    if (inside == _locationInMalaysia) return;
    _locationInMalaysia = inside;
    safeNotifyListeners();
  }

  static double _clampZoom(double zoom) => zoom.clamp(
    DiscoveryLogicFacade.minimumZoom,
    DiscoveryLogicFacade.maximumZoom,
  );
}
