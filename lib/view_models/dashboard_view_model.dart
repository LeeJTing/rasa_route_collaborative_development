import 'dart:async';

import 'package:meta/meta.dart' show visibleForTesting;

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/exploration_filter.dart';
import '../domain_model/exploration_search.dart';
import '../domain_model/food_distribution.dart';
import '../domain_model/local_food.dart';
import '../domain_model/map.dart';
import '../domain_model/matches_recommendation.dart';
import '../domain_model/region.dart';
import '../domain_model/swipe_mode.dart';
import '../domain_model/swipe_session.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/discovery_logic_facade.dart';

/// Which of the two dashboard maps is showing (REQ102_12, REQ102_13).
enum DashboardMapMode { heatmap, detailed }

/// Temporary hand-off for the dashboard map -> landmark detail jump.
///
/// Routes pass no arguments (Developer Guideline, section 7.2 "Open
/// decision") and a ViewModel takes no constructor parameters (Rule 1), so
/// when the map's "View Landmark" button is tapped the dashboard stashes the
/// tapped pin's `landmark_id` here right before pushing
/// `AppRoutes.landmarkPlaceDetail`, and `LandmarkPlaceDetailView` reads-and-
/// clears it in `initState` - the same pattern `LandmarkDraftHandoff` uses
/// for the recognition flow.
class MapSelectionHandoff {
  factory MapSelectionHandoff() => _instance;

  MapSelectionHandoff._();

  static final MapSelectionHandoff _instance = MapSelectionHandoff._();

  /// The `submitted_landmark.landmark_id` behind the tapped landmark pin.
  int? pendingLandmarkId;

  int? takeLandmarkId() {
    final int? value = pendingLandmarkId;
    pendingLandmarkId = null;
    return value;
  }
}

/// ViewModel for `DashboardView` - REQ102, the Local Food Dashboard &
/// Regional Exploration Module, following UC300.

class DashboardViewModel extends BaseViewModel {
  DashboardViewModel({@visibleForTesting DiscoveryLogicFacade? discoveryLogic})
    : discoveryLogic = discoveryLogic ?? DiscoveryLogicFacade() {
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

  static TouristLocation _sharedLocation = TouristLocation.unknown;

  /// The most recent GPS fix, shared by every instance of this ViewModel.
  static TouristLocation get sharedLocation => _sharedLocation;

  // ===========================================================================
  // Somebody else changed the map
  // ===========================================================================
  //
  //   RestaurantMonitor -> UpdateRestaurantFacade.publishMapDataChanged()
  //                     -> DashboardViewModel.onMapDataChanged()   [here]
  //
  // Static for the same reason the location fix is: the prompt has to survive
  // this ViewModel being disposed and rebuilt, or switching tabs would quietly
  // lose it.

  static int _pendingNewLandmarks = 0;
  static bool _mapUpdatePending = false;

  /// **Called by `UpdateRestaurantFacade`, which `RestaurantMonitor` calls.**
  /// Nothing else should call it.
  ///
  /// Note it only raises a flag. Re-fetching here would swap the map out from
  /// under a tourist mid-read; the dashboard asks first.
  static void onMapDataChanged({required int newLandmarks}) {
    _mapUpdatePending = true;
    _pendingNewLandmarks = newLandmarks;
    for (final DashboardViewModel viewModel in Set<DashboardViewModel>.of(
      _live,
    )) {
      viewModel.safeNotifyListeners();
    }
  }

  /// Whether the map on screen has fallen behind the database.
  bool get mapUpdateAvailable => _mapUpdatePending;

  /// What the prompt says. Names a number when there is one, because "2 new
  /// landmarks" is worth tapping and "something changed" is not.
  String get mapUpdateMessage => _pendingNewLandmarks > 0
      ? '$_pendingNewLandmarks new landmark'
            '${_pendingNewLandmarks == 1 ? '' : 's'} added by other tourists.'
      : 'The map has new places since you opened it.';

  /// The Update button. Drops the caches, re-reads whichever view is showing,
  /// and leaves the camera exactly where it was.
  Future<void> applyMapUpdate() async {
    _mapUpdatePending = false;
    _pendingNewLandmarks = 0;
    discoveryLogic.clearMapCache();
    safeNotifyListeners();
    await _reloadActiveView();
  }

  /// Dismissed without refreshing. The next change re-raises it.
  void dismissMapUpdate() {
    if (!_mapUpdatePending) return;
    _mapUpdatePending = false;
    _pendingNewLandmarks = 0;
    safeNotifyListeners();
  }

  /// **Called by `CurrentLocationFacade`, which `LocationMonitor` calls.**
  /// Nothing else should call it.
  static void onCurrentLocationChanged(TouristLocation location) {
    final bool lost = _sharedLocation.isKnown && !location.isKnown;
    _sharedLocation = location;
    for (final DashboardViewModel viewModel in Set<DashboardViewModel>.of(
      _live,
    )) {
      viewModel._onLocationPushed(lost: lost);
    }
  }

  final DiscoveryLogicFacade discoveryLogic;

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
  int _pinLoadRevision = 0;
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

  final Set<ExplorationFilterGroup> _expandedGroups =
      <ExplorationFilterGroup>{};
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
  bool _targetFrameOwnsSelection = false;

  // ===========================================================================
  // Location (REQ102_6 - REQ102_9, REQ102_14)
  // ===========================================================================

  /// Reads the shared fix, so a freshly built ViewModel starts with whatever
  /// the monitor last published rather than `unknown`.
  TouristLocation get location => _sharedLocation;

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

  SwipeModePreparation? _swipePreparation;
  SwipeSession? _swipeSession;
  bool _swipeLoading = false;
  String? _swipeError;
  bool _showSwipeResumePrompt = false;
  int _swipeLikeRevision = 0;
  int _swipePrepareRevision = 0;

  bool get swipeLoading => _swipeLoading;
  String? get swipeError => _swipeError;
  bool get showSwipeResumePrompt => _showSwipeResumePrompt;
  String get swipeStateName => _swipePreparation?.stateName ?? 'this state';
  int get swipeLikeRevision => _swipeLikeRevision;

  int get savedSwipeCardCount {
    final SwipeSession? saved = _swipePreparation?.savedSession;
    if (saved == null || saved.candidateFoodIds.isEmpty) return 0;
    return (saved.currentIndex + 1).clamp(0, saved.candidateFoodIds.length);
  }

  int get savedSwipeLikeCount =>
      _swipePreparation?.savedSession?.likedFoodIds.length ?? 0;

  int get savedSwipeRestaurantCount =>
      _swipePreparation?.savedRestaurantCount ?? 0;

  List<LocalFood> get swipeQueue {
    final SwipeModePreparation? preparation = _swipePreparation;
    if (preparation == null) return const <LocalFood>[];
    final Map<int, LocalFood> byId = <int, LocalFood>{
      for (final LocalFood food in preparation.queue) food.id: food,
    };
    final List<int> ids =
        _swipeSession?.candidateFoodIds ??
        preparation.queue.map((LocalFood food) => food.id).toList();
    return ids.map((int id) => byId[id]).whereType<LocalFood>().toList();
  }

  LocalFood? get currentSwipeFood {
    final List<LocalFood> queue = swipeQueue;
    final int index = _swipeSession?.currentIndex ?? 0;
    return index >= 0 && index < queue.length ? queue[index] : null;
  }

  LocalFood? get previousSwipeFood {
    final List<LocalFood> queue = swipeQueue;
    final int index = (_swipeSession?.currentIndex ?? 0) - 1;
    return index >= 0 && index < queue.length ? queue[index] : null;
  }

  LocalFood? get nextSwipeFood {
    final List<LocalFood> queue = swipeQueue;
    final int index = (_swipeSession?.currentIndex ?? 0) + 1;
    return index >= 0 && index < queue.length ? queue[index] : null;
  }

  bool get currentSwipeFoodRestricted {
    final int? foodId = currentSwipeFood?.id;
    return foodId != null &&
        (_swipePreparation?.restrictedFoodIds.contains(foodId) ?? false);
  }

  bool get currentSwipeFoodLiked {
    final int? foodId = currentSwipeFood?.id;
    return foodId != null &&
        (_swipeSession?.likedFoodIds.contains(foodId) ?? false);
  }

  /// REQ103_1 calls the Discovery Layer Bar "a sliding bottom-sheet", so it has
  /// a collapsed peek and an expanded state. It starts collapsed: expanded it
  /// is 236pt, which is 40% of the map on a 390x844 phone, and until REQ103
  /// fills it there is nothing in there worth that much screen.
  bool get swipePanelExpanded => _swipePanelExpanded;

  void toggleSwipePanel() {
    _swipePanelExpanded = !_swipePanelExpanded;
    safeNotifyListeners();
    if (_swipePanelExpanded) {
      if (_swipePreparation == null) {
        _prepareSwipeModeForActiveState();
      } else if (!_showSwipeResumePrompt) {
        showFoodInTargetFrame(currentSwipeFood);
      }
    } else {
      showFoodInTargetFrame(null);
    }
  }

  Future<void> continueSwipeSession() async {
    final SwipeModePreparation? preparation = _swipePreparation;
    if (preparation == null || _swipeLoading) return;
    await _runSwipeCommand(() async {
      _swipeSession = await discoveryLogic.continueSwipeSession(preparation);
      _showSwipeResumePrompt = false;
      showFoodInTargetFrame(currentSwipeFood);
    });
  }

  Future<void> startNewSwipeSession() async {
    final SwipeModePreparation? preparation = _swipePreparation;
    if (preparation == null || _swipeLoading) return;
    await _runSwipeCommand(() async {
      _swipeSession = await discoveryLogic.startNewSwipeSession(preparation);
      _showSwipeResumePrompt = false;
      showFoodInTargetFrame(currentSwipeFood);
    });
  }

  Future<void> showPreviousSwipeFood() => _moveSwipeFoodBy(-1);

  Future<void> showNextSwipeFood() => _moveSwipeFoodBy(1);

  Future<void> _moveSwipeFoodBy(int amount) async {
    final SwipeSession? session = _swipeSession;
    if (session == null || _swipeLoading) return;
    final int requested = session.currentIndex + amount;
    if (requested < 0 || requested >= session.candidateFoodIds.length) return;
    await _runSwipeCommand(() async {
      _swipeSession = await discoveryLogic.moveSwipeSession(session, requested);
      showFoodInTargetFrame(currentSwipeFood);
    }, showLoading: false);
  }

  Future<void> likeCurrentSwipeFood() async {
    final SwipeSession? session = _swipeSession;
    final LocalFood? food = currentSwipeFood;
    if (session == null ||
        food == null ||
        currentSwipeFoodLiked ||
        _swipeLoading) {
      return;
    }
    await _runSwipeCommand(() async {
      _swipeSession = await discoveryLogic.likeSwipeFood(session, food.id);
      _swipeLikeRevision++;
    }, showLoading: false);
  }

  /// The card gesture only adds a match, while the explicit heart control is
  /// a toggle so a tourist can remove an accidental match in place.
  Future<void> toggleCurrentSwipeFoodLike() async {
    final SwipeSession? session = _swipeSession;
    final LocalFood? food = currentSwipeFood;
    if (session == null || food == null || _swipeLoading) return;

    if (!currentSwipeFoodLiked) {
      await likeCurrentSwipeFood();
      return;
    }

    await _runSwipeCommand(() async {
      _swipeSession = await discoveryLogic.removeSwipeFoodLike(
        session,
        food.id,
      );
      _swipeLikeRevision++;
    }, showLoading: false);
  }

  /// REQ102_10 - the Discovery Layer Bar appears with the detailed map view.
  bool get showSwipePanel => isDetailedView;

  /// REQ102_11 / A9 - the tourist starts Quick Mode from the detailed map.
  /// Permission, a fresh fix and the Malaysia boundary are checked on tap.
  bool get showQuickModeButton => isDetailedView;

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
  void _onLocationPushed({bool lost = false}) {
    // Say why the marker vanished. Silently removing it looks like a glitch.
    if (lost) {
      _notice =
          'Location is off, so the map cannot show where you are. '
          'Turn it on to use Find Me and Quick Mode.';
    }
    safeNotifyListeners();
    _refreshWithinMalaysia();
  }

  @override
  void dispose() {
    _pinRefreshTimer?.cancel();
    _swipePrepareRevision++;
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
    // Tapping Find Me again while it is still working must not stack a second
    // request behind the first - that is how one slow fix turns into a spinner
    // that outlives several taps.
    if (_locating) return;

    _locating = true;
    _locationPermissionGranted = false;
    _locationInMalaysia = false;
    safeNotifyListeners();
    try {
      // Both awaits are bounded here as well as in the device layer. The
      // spinner is driven by `_locating`, so anything that can hang below has
      // to be capped above too, or the button spins forever.
      _locationPermissionGranted = await discoveryLogic
          .ensureLocationPermission()
          .timeout(_locateTimeout, onTimeout: () => false);

      if (!_locationPermissionGranted) {
        _locationInMalaysia = false;
        _notice =
            'Location permission is off, so the map is showing all of '
            'Malaysia. Turn it on to centre on where you are.';
        _showMalaysiaOverview();
        return;
      }

      final TouristLocation fix = await discoveryLogic
          .currentLocation()
          .timeout(_locateTimeout, onTimeout: () => TouristLocation.unknown);
      _sharedLocation = fix;

      if (!fix.isKnown) {
        // Say so. Silently falling back to the country view looks like the
        // button did nothing.
        _locationInMalaysia = false;
        _notice =
            'Could not get your location. Check that GPS is switched on, '
            'then try Find Me again.';
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
  // Dev GPS mock (presenter tool, Android only)
  // ===========================================================================
  //
  //   _MockGpsButton -> DashboardViewModel -> DiscoveryLogicFacade
  //                 -> MapExplorationLogic -> LocationRepository
  //                 -> MockLocationService (OS test provider)
  //
  // While a mock is active `LocationMonitor` holds the mocked fix and ignores
  // the real GPS, so the map stays put until the mock is stopped.

  /// Whether this build can mock the OS GPS (Android, non-web). The View hides
  /// the dev control when false.
  bool get mockGpsSupported => discoveryLogic.mockGpsSupported;

  /// Whether a mock is live right now.
  bool get mockGpsActive => discoveryLogic.mockGpsActive;

  /// Teleports the OS GPS to a preset spot. Returns an error message, or null
  /// on success.
  Future<String?> setMockGps(double latitude, double longitude) async {
    final String? error = await discoveryLogic.setMockGps(
      latitude: latitude,
      longitude: longitude,
    );
    safeNotifyListeners();
    return error;
  }

  /// Stops mocking and lets the real GPS drive the map again.
  Future<void> stopMockGps() async {
    await discoveryLogic.stopMockGps();
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
      if (next == DashboardMapMode.heatmap) {
        _heatmapResetToken++;
        _leaveSwipeModeForHeatmap();
      }
      safeNotifyListeners();
      if (_mode == DashboardMapMode.detailed) {
        _loadPins();
        _prepareSwipeModeForActiveState();
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
      _refreshSwipeModeRegion();
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

  /// A11-4 - open the full details page for the selected pin: the full
  /// Restaurant Details page for a system restaurant, or the full Landmark
  /// Details page for a tourist-submitted landmark. The landmark screen has
  /// no route arguments, so the pin's `landmark_id` rides the
  /// [MapSelectionHandoff] instead.
  void openSelectedPin() {
    final MapPin? pin = _selectedPin;
    if (pin == null) return;

    if (pin.kind == MapPinKind.landmark) {
      final int? landmarkId = int.tryParse(pin.referenceId);

      if (landmarkId == null || landmarkId <= 0) {
        _notice = 'This landmark does not have a valid details reference.';
        safeNotifyListeners();
        return;
      }

      MapSelectionHandoff().pendingLandmarkId = landmarkId;
      AppNavigator.push(AppRoutes.landmarkPlaceDetail);
      return;
    }

    final int? restaurantId = int.tryParse(pin.referenceId);

    if (restaurantId == null || restaurantId <= 0) {
      _notice = 'This restaurant does not have a valid details reference.';
      safeNotifyListeners();
      return;
    }

    AppNavigator.push(AppRoutes.restaurantDetail, arguments: restaurantId);
  }

  // ===========================================================================
  // Quick Mode (A9, REQ102_11)
  // ===========================================================================

  Future<void> openQuickMode() async {
    // A9 step 2 happens after the icon is selected. Do not rely on an old
    // background fix: permission or GPS may have changed since it arrived.
    await locateTourist();
    if (!_locationPermissionGranted || !_sharedLocation.isKnown) return;
    if (!_locationInMalaysia) {
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
    _targetFrameOwnsSelection = false;
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
    // An asynchronous session preparation/command may finish after the sheet
    // has been collapsed. It must not reactivate the Swipe-owned map filter.
    if (food != null && !_swipePanelExpanded) return;
    _targetFrameOwnsSelection = food != null;
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
    _targetFrameOwnsSelection = false;
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
  int get matchesCount => _swipeSession?.likedFoodIds.length ?? 0;

  MatchesRecommendationRequest get matchesRecommendationRequest =>
      MatchesRecommendationRequest(
        stateCode: _swipePreparation?.stateCode ?? '',
        stateName: _swipePreparation?.stateName ?? '',
        origin: TouristLocation(
          latitude: _centreLatitude,
          longitude: _centreLongitude,
        ),
      );

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

  /// Ceiling on one Find Me attempt, a little above the device layer's own so
  /// that layer gets to answer first when it can.
  static const Duration _locateTimeout = Duration(seconds: 16);

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

  Future<void> _refreshSwipeModeRegion() async {
    final Region? region = await discoveryLogic.regionAt(
      _centreLatitude,
      _centreLongitude,
    );
    if (region == null || region.code == _swipePreparation?.stateCode) return;
    await _prepareSwipeModeForActiveState();
  }

  Future<void> _prepareSwipeModeForActiveState() async {
    if (!isDetailedView) return;
    final int revision = ++_swipePrepareRevision;
    _swipeLoading = true;
    _swipeError = null;
    safeNotifyListeners();
    try {
      final SwipeModePreparation preparation = await discoveryLogic
          .prepareSwipeMode(
            latitude: _centreLatitude,
            longitude: _centreLongitude,
          );
      if (revision != _swipePrepareRevision || !isDetailedView) return;
      _swipePreparation = preparation;
      _swipeSession = null;
      _showSwipeResumePrompt = preparation.savedSession != null;
      if (!_showSwipeResumePrompt) {
        _swipeSession = await discoveryLogic.startNewSwipeSession(preparation);
      }
      if (_swipePanelExpanded && !_showSwipeResumePrompt) {
        showFoodInTargetFrame(currentSwipeFood);
      }
    } catch (error) {
      if (revision != _swipePrepareRevision) return;
      _swipeError = _humaniseSwipeError(error);
      _swipePreparation = null;
      _swipeSession = null;
      _showSwipeResumePrompt = false;
      if (_swipePanelExpanded) showFoodInTargetFrame(null);
    } finally {
      if (revision == _swipePrepareRevision) {
        _swipeLoading = false;
        safeNotifyListeners();
      }
    }
  }

  Future<void> _runSwipeCommand(
    Future<void> Function() command, {
    bool showLoading = true,
  }) async {
    if (showLoading) _swipeLoading = true;
    _swipeError = null;
    safeNotifyListeners();
    try {
      await command();
    } catch (error) {
      _swipeError = _humaniseSwipeError(error);
    } finally {
      if (showLoading) _swipeLoading = false;
      safeNotifyListeners();
    }
  }

  static String _humaniseSwipeError(Object error) {
    final String message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  void _leaveSwipeModeForHeatmap() {
    _swipePrepareRevision++;
    _swipePanelExpanded = false;
    _swipePreparation = null;
    _swipeSession = null;
    _swipeLoading = false;
    _swipeError = null;
    _showSwipeResumePrompt = false;
    if (_targetFrameOwnsSelection) {
      _selectedFood = null;
      _targetFrameOwnsSelection = false;
    }
  }

  Future<void> _loadHeatmap() => runGuarded(() async {
    _pinLoadRevision++;
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
    final int revision = ++_pinLoadRevision;
    final int? requestedFoodId = _activePinFoodId;
    if (clearFirst && _pins.isNotEmpty) {
      _pins = const <MapPin>[];
      safeNotifyListeners();
    }

    _lastPinLatitude = _centreLatitude;
    _lastPinLongitude = _centreLongitude;
    _lastPinZoom = _zoom;
    final List<MapPin> loadedPins = await discoveryLogic.mapPins(
      filter: _filter,
      localFoodId: requestedFoodId,
      south: _viewportSouth,
      west: _viewportWest,
      north: _viewportNorth,
      east: _viewportEast,
      fromLatitude: _sharedLocation.isKnown ? _sharedLocation.latitude : null,
      fromLongitude: _sharedLocation.isKnown ? _sharedLocation.longitude : null,
    );
    if (revision != _pinLoadRevision || requestedFoodId != _activePinFoodId) {
      return;
    }
    _pins = loadedPins;
  }, silent: true);

  int? get _activePinFoodId => _targetFrameOwnsSelection && !_swipePanelExpanded
      ? null
      : _selectedFood?.id;

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
      if (next == DashboardMapMode.heatmap) {
        _heatmapResetToken++;
        _leaveSwipeModeForHeatmap();
      }
    }

    safeNotifyListeners();

    if (changed) {
      if (next == DashboardMapMode.detailed) {
        _loadPins();
        _prepareSwipeModeForActiveState();
      } else {
        _loadHeatmap();
      }
    }
  }

  Future<void> _refreshWithinMalaysia() async {
    // Losing the fix has to clear this, not just skip the check. It gates the
    // Quick Mode button (REQ102_11), so an early return here left Quick Mode
    // on screen after the tourist switched GPS off.
    if (!_sharedLocation.isKnown) {
      if (!_locationInMalaysia) return;
      _locationInMalaysia = false;
      safeNotifyListeners();
      return;
    }

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
