import 'dart:async';

import 'package:meta/meta.dart' show protected;

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
import 'current_location_facade.dart';

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
  DashboardViewModel() {
    _live.add(this);
  }

  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

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

  /// Called by `UpdateRestaurantFacade.publishOwnMapDataChanged` when THIS
  /// tourist changed the map themselves - e.g. a report they just submitted
  /// froze the landmark/restaurant they were viewing. Unlike [onMapDataChanged]
  /// there is no "update available" banner (it was their own action, not a
  /// background change), so each live dashboard silently drops its map caches
  /// and re-reads whatever view is showing - the frozen place's pin disappears.
  static void onOwnMapDataChanged() {
    for (final DashboardViewModel viewModel in Set<DashboardViewModel>.of(
      _live,
    )) {
      viewModel._refreshAfterOwnChange();
    }
  }

  Future<void> _refreshAfterOwnChange() async {
    discoveryLogic.clearMapCache();
    safeNotifyListeners();
    await _reloadActiveView();
    // The tourist's own change froze the place whose card they had open - it
    // is no longer 'available', so its pin is gone and the open card must go
    // with it instead of lingering over the refreshed map.
    _dismissSelectedPinIfNoLongerPinned();
  }

  /// Closes the open pin card when the pin it points at is no longer in the
  /// freshly loaded [pins] - e.g. after this tourist's report froze the place
  /// and it stopped being 'available'. No-op when nothing is selected or the
  /// pin is still there (a report below the freeze threshold changes nothing
  /// on the map).
  void _dismissSelectedPinIfNoLongerPinned() {
    final MapPin? selected = _selectedPin;
    if (selected == null) return;
    final bool stillPinned = _pins.any(
      (MapPin pin) =>
          pin.kind == selected.kind && pin.referenceId == selected.referenceId,
    );
    if (!stillPinned) {
      _selectedPin = null;
      _rebuildVisibleMarkers();
      safeNotifyListeners();
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

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();

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

  /// What the map draws: the loaded pins, plus the members of a cluster that
  /// was opened because no zoom could ever separate them.
  ///
  /// Combined once per load rather than in the getter - the View reads this on
  /// every rebuild, and a getter that allocated would allocate every frame.
  List<MapPin> _visiblePins = const <MapPin>[];
  List<MapPin> get pins => _visiblePins;

  List<MapCluster> _visibleClusters = const <MapCluster>[];

  /// A cluster whose members share coordinates, opened into individual pins.
  /// Its badge is removed from the map while its members are drawn.
  MapCluster? _expandedCluster;
  List<MapPin> _expandedPins = const <MapPin>[];

  /// **The temporary search layer, drawn on top of the filtered map.**
  ///
  /// A keyword adds markers; it never replaces the ones the filter chips are
  /// drawing. The two answer different questions - the chips say "what am I in
  /// the mood for", a keyword says "where is this one thing" - and answering
  /// the second by throwing away the first is how a tourist loses the map they
  /// spent four taps building.
  ///
  /// What it does **not** relax: `available` only, and the current viewport.
  /// Those are not filters, they are what the map is.
  /// What the keyword last matched, kept separately from [_searchResults]
  /// because the two are cleared at different moments: picking one result
  /// closes the result list, and must not take the markers with it.
  ExplorationSearchResults _searchLayerFor = ExplorationSearchResults.empty;

  /// The same answer, in the shape the marker query wants it.
  ///
  /// **There is no second query and no second marker list.** Search results and
  /// the filtered map are one set, grouped by one grid, in one request; this is
  /// the half of that request the keyword owns. Empty when no keyword is
  /// active, and the query is then exactly what it always was.
  MapSearchSelection _searchSelection = MapSearchSelection.none;

  /// Whether a keyword is currently adding anything to the map.
  bool get hasSearchPins => _searchSelection.isNotEmpty;

  /// Is this marker a search result rather than part of the filtered map?
  ///
  /// Read off the marker, because Postgres is what decided it: one grid over
  /// both sets, and `search_count` on the row says which set the place came
  /// from. This used to be a set of keys maintained here, which was the client
  /// re-deriving something the server already knew.
  bool isSearchPin(MapPin pin) => pin.isSearchResult;

  void _rebuildVisibleMarkers() {
    final MapCluster? expanded = _expandedCluster;

    // One list. The members of an opened cluster join the pins that were
    // already drawn, and each one carries its own type, so nothing here has to
    // know which of them a keyword is responsible for.
    final List<MapPin> drawn = _expandedPins.isEmpty
        ? _pins
        : <MapPin>[..._pins, ..._expandedPins];

    // **The open place always has a marker.** The pins come from the viewport
    // query, which answers the current filter and zoom cap - so a restaurant
    // reached by searching for it by name could have its detail sheet open
    // over a map with nothing at the centre, because the query that filled the
    // map was never asked about it. Whatever is selected is drawn, whether or
    // not the query returned it.
    final MapPin? selected = _selectedPin;
    final bool alreadyDrawn =
        selected == null ||
        drawn.any(
          (MapPin pin) =>
              pin.referenceId == selected.referenceId &&
              pin.kind == selected.kind,
        );

    _visiblePins = List<MapPin>.unmodifiable(
      alreadyDrawn ? drawn : <MapPin>[...drawn, selected],
    );
    // An opened cluster loses its badge while its members are drawn.
    _visibleClusters = expanded == null
        ? _clusters
        : List<MapCluster>.unmodifiable(
            _clusters.where((MapCluster c) => c.key != expanded.key),
          );
  }

  void _collapseExpandedCluster() {
    if (_expandedCluster == null && _expandedPins.isEmpty) return;
    _expandedCluster = null;
    _expandedPins = const <MapPin>[];
  }

  // ---------------------------------------------------------------------------
  // How much of the answer is on screen
  // ---------------------------------------------------------------------------
  //
  // Postgres folds each grid cell into one marker, so what arrives is already
  // a screenful whatever the zoom. These carry the rest of the truth so the
  // View can say what stands behind the markers.

  int _pinsInView = 0;
  int _pinLimit = 0;

  /// Every place inside the current viewport that matched, drawn or not.
  int get pinsInView => _pinsInView;

  /// The cap the current zoom allows.
  int get pinLimit => _pinLimit;

  /// Matching places in view that did not fit on the map.
  int get hiddenPinCount {
    final int hidden = _pinsInView - _pins.length;
    return hidden > 0 ? hidden : 0;
  }

  /// REQ102_41 - the grid cells that held more than one place, drawn as counts.
  ///
  /// Populated **alongside** [pins], not instead of them: the group-or-not
  /// decision is made per cell, so a screen normally carries some of each and
  /// zooming in converts clusters into pins as the cells shrink.
  List<MapCluster> _clusters = const <MapCluster>[];
  List<MapCluster> get clusters => _visibleClusters;

  /// Whether any marker on screen stands for more than one place.
  bool get isClustered => isDetailedView && _visibleClusters.isNotEmpty;

  /// What the markers on screen stand for: every pin, plus everything inside
  /// every cluster.
  int get placesOnMap =>
      _visiblePins.length +
      _visibleClusters.fold<int>(0, (int sum, MapCluster c) => sum + c.count);

  /// The state under the middle of the detailed map, as the heatmap counted it.
  ///
  /// This is the heatmap's own number reused: `RegionAvailability
  /// .placeCount` is the distinct places in that state matching the active
  /// filter (C1's numerator), so the detailed view can put the pins on screen
  /// in proportion without counting anything a second time.
  RegionAvailability? _regionInView;
  RegionAvailability? get regionInView => _regionInView;

  /// "Selangor - 1,432 places in this state", from the heatmap tally.
  ///
  /// Says *matching* when a filter or a Target Frame dish is narrowing the
  /// count, because that is what the heatmap counted - claiming a plain total
  /// while a filter is on would be a different number entirely.
  String? get regionInViewMessage {
    final RegionAvailability? availability = _regionInView;
    if (availability == null || !isDetailedView) return null;
    final int count = availability.placeCount;
    if (count == 0) return null;
    final bool narrowed =
        _filter.selectionCount > 0 || _activePinFoodId != null;
    return '${availability.region.name} - $count '
        '${narrowed ? 'matching ' : ''}'
        '${count == 1 ? 'place' : 'places'} in this state';
  }

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

  /// What the map is drawing right now - the applied filter.
  ExplorationFilter _filter = ExplorationFilter.none;
  ExplorationFilter get filter => _filter;

  /// What the open panel is showing, which is not yet what the map is drawing.
  ///
  /// Every chip used to reload the map on the tap: four chips meant four round
  /// trips, three of them for a filter the tourist was still in the middle of
  /// describing. The panel now edits this copy and [applyFilter] promotes it in
  /// one go, so a visit to the filter costs one request however many chips it
  /// takes. Leaving without applying drops the draft and the active filter
  /// stands (A7-5).
  ExplorationFilter _draftFilter = ExplorationFilter.none;

  bool _filterPanelOpen = false;
  bool get filterPanelOpen => _filterPanelOpen;

  final Set<ExplorationFilterGroup> _expandedGroups =
      <ExplorationFilterGroup>{};
  bool isGroupExpanded(ExplorationFilterGroup group) =>
      _expandedGroups.contains(group);

  List<String> optionsFor(ExplorationFilterGroup group) =>
      discoveryLogic.filterOptions(group);

  /// The options ticked in [group], empty for "All".
  ///
  /// The *draft*, because this is what the panel draws its chips from: a tick
  /// has to look ticked long before it reaches the map.
  Set<String> selectionFor(ExplorationFilterGroup group) =>
      _draftFilter.selectionFor(group);

  /// How many chips are ticked in the panel - the count on its Apply button.
  int get draftSelectionCount => _draftFilter.selectionCount;

  /// Does the panel hold anything the map has not been told about yet?
  bool get filterDraftChanged => !_sameFilter(_draftFilter, _filter);

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

  /// Whether a keyword is currently driving the map.
  ///
  /// Distinct from [searching], which means "a request is in flight". This is
  /// true from the first character typed until the field is cleared - and it
  /// stays true after a result has been picked, because picking one leaves the
  /// keyword in the box and its markers on the map.
  ///
  /// **Swipe Mode is unavailable while this is true.** The Target Frame and a
  /// keyword are two claims on the same map: the frame narrows every marker to
  /// one dish, the keyword adds markers the chips never asked for, and a
  /// tourist looking at both has no way to tell which one is answering. The
  /// search is what the tourist asked for most recently, so it wins; the
  /// Discovery Layer Bar comes back the moment the search is cleared.
  bool get hasActiveSearch => _searchKeyword.trim().isNotEmpty;

  /// A8.2 / M2 - shown under the search field when nothing matched.
  String? _searchMessage;
  String? get searchMessage => _searchMessage;

  static const String noResultMessage =
      'No location or local food matches your input. Please try again.';

  static const String notInMalaysiaMessage =
      'You are not in Malaysia, you are not allowed to use Quick Mode.';

  /// Shown when a search closes an open Discovery Layer Bar. Named rather
  /// than written inline, so the banner can be taken down again by the code
  /// that puts the bar back, and only when it is this banner that is up.
  static const String swipePausedNotice =
      'Swipe Mode is paused while you are searching. '
      'Clear the search to carry on swiping.';

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

  /// REQ102_7 / A3 - whether to draw the tourist's own position at all.
  ///
  /// **A known fix is not enough; it has to be inside Malaysia.** Both surfaces
  /// only cover this country - the overview is a stylised projection of it, and
  /// the detailed map masks everything else out - so a fix in Singapore or
  /// Jakarta gets drawn at whatever those coordinates map to *inside* the
  /// frame, which is a position the tourist is not at. Showing nothing is the
  /// honest answer, and A3 already explains why with a notice.
  bool get showCurrentLocation =>
      _sharedLocation.isKnown && _locationInMalaysia;

  bool _swipePanelExpanded = false;

  SwipeModePreparation? _swipePreparation;
  SwipeSession? _swipeSession;
  bool _swipeLoading = false;
  String? _swipeError;
  bool _showSwipeResumePrompt = false;
  int _swipeLikeRevision = 0;
  int _swipePrepareRevision = 0;
  bool _swipeQueueUpdatePending = false;
  bool _swipeQueueProfileChanged = false;
  double? _swipeQueueSouth;
  double? _swipeQueueWest;
  double? _swipeQueueNorth;
  double? _swipeQueueEast;

  bool get swipeLoading => _swipeLoading;
  String? get swipeError => _swipeError;
  bool get showSwipeResumePrompt => _showSwipeResumePrompt;
  String get swipeStateName => _swipePreparation?.stateName ?? 'this state';
  int get swipeLikeRevision => _swipeLikeRevision;
  bool get swipeQueueUpdateAvailable =>
      _swipePanelExpanded && _swipeQueueUpdatePending;
  String get swipeQueueUpdateMessage => _swipeQueueProfileChanged
      ? 'Your preferences changed. Update the food queue?'
      : 'The map area changed. Update foods for this view?';

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
    // The bar is off screen while a keyword is active, so this cannot be
    // reached by tapping it. It is the guard for any other route in, and for
    // a tap racing the keystroke that started the search.
    if (hasActiveSearch) return;
    _swipePanelExpanded = !_swipePanelExpanded;
    safeNotifyListeners();
    if (_swipePanelExpanded) {
      if (_swipePreparation == null) {
        _prepareSwipeModeForActiveState();
      } else if (!_showSwipeResumePrompt) {
        showFoodInTargetFrame(currentSwipeFood);
        _offerSwipeQueueUpdateIfViewportChanged();
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

  /// REQ102_10 - the Discovery Layer Bar appears with the detailed map view,
  /// and only while no keyword is active.
  ///
  /// A search owns the map and so does Swipe Mode; they cannot both have it.
  /// See [hasActiveSearch].
  bool get showSwipePanel => isDetailedView && !hasActiveSearch;

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
    _searchDebounce?.cancel();
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
      // Quick Mode reads its origin from the inbound location facade. Publish
      // this user-requested fix immediately so the destination screen cannot
      // race the background monitor and search from an older position.
      CurrentLocationFacade().publish(fix);

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
    double? swipeSouth,
    double? swipeWest,
    double? swipeNorth,
    double? swipeEast,
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
    _swipeViewportSouth = swipeSouth;
    _swipeViewportWest = swipeWest;
    _swipeViewportNorth = swipeNorth;
    _swipeViewportEast = swipeEast;

    final DashboardMapMode next = zoom >= DiscoveryLogicFacade.detailedViewZoom
        ? DashboardMapMode.detailed
        : DashboardMapMode.heatmap;

    if (next != _mode) {
      _mode = next;
      _selectedRegion = null;
      _selectedPin = null;
      _rebuildVisibleMarkers();
      if (next == DashboardMapMode.heatmap) {
        _heatmapResetToken++;
        _heatmapScale = 1;
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
    _pinRefreshTimer = Timer(_pinRefreshDelay, () async {
      if (_mode != DashboardMapMode.detailed) return;
      // Moving the map changes the visible pins, not the active Swipe deck.
      // Re-localising an expanded deck here would replace its state-scoped
      // session and reopen the Continue/New prompt while the tourist pans.
      if (!_swipePanelExpanded && !hasActiveSearch) {
        await _refreshSwipeModeRegion();
      }
      if (_swipePanelExpanded) _offerSwipeQueueUpdateIfViewportChanged();
      if (_mode != DashboardMapMode.detailed) return;
      // One load, whether or not a keyword is active: the search half rides
      // along inside the same query.
      if (_viewportChangedSinceLastPinLoad()) await _loadPins();
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

  /// A11 - a marker was tapped.
  ///
  /// The sheet opens immediately on what the marker already carries - name,
  /// photo, rating, distance - and the rest (category, menu, price range, open
  /// now) is fetched by id and filled in a moment later. Map markers are
  /// deliberately lightweight; this is where the full row is read.
  void selectPin(MapPin pin) {
    final int revision = ++_pinDetailRevision;
    _selectedPin = pin;
    _pinDetailLoading = true;
    // The selected place is drawn whether or not the viewport query returned
    // it, so the marker list has to be rebuilt when the selection changes.
    _rebuildVisibleMarkers();
    safeNotifyListeners();
    _loadPinDetail(pin, revision);
  }

  int _pinDetailRevision = 0;
  bool _pinDetailLoading = false;

  /// Whether the tapped pin's full detail is still on its way.
  bool get pinDetailLoading => _pinDetailLoading;

  Future<void> _loadPinDetail(MapPin pin, int revision) async {
    final MapPin detailed = await discoveryLogic.mapPinDetail(
      pin,
      filter: _filter,
      localFoodId: _activePinFoodId,
    );
    // Tapping a second pin, or dismissing the sheet, wins over a slower reply
    // for the first.
    if (revision != _pinDetailRevision) return;
    if (_selectedPin?.referenceId != pin.referenceId ||
        _selectedPin?.kind != pin.kind) {
      return;
    }
    _selectedPin = detailed;
    _pinDetailLoading = false;
    safeNotifyListeners();
  }

  /// REQ102_41 - tapping a cluster opens it.
  ///
  /// It used to zoom a fixed two levels, which for a dense metro was not enough
  /// to break the grid cell up: the same count came back and the tap looked like
  /// nothing happened, three or four times in a row. Postgres now works out
  /// where to go, and the tap goes straight there.
  ///
  /// When no zoom separates the members - places at the same coordinates - the
  /// map goes to maximum zoom and draws every member individually instead, so a
  /// cluster is never a dead end.
  /// [searchLayer] says which of the two cluster layers was tapped. The
  /// behaviour is identical - zoom until it splits, draw the members when no
  /// zoom ever will - but a search cluster has to be opened against the dishes
  /// the keyword matched rather than the filter chips, or the probe answers
  /// about a different set of places and hands back a split zoom that does not
  /// split this badge.
  Future<void> zoomIntoCluster(MapCluster cluster) async {
    if (_clusterOpening) return;
    _clusterOpening = true;
    try {
      final ClusterExpansion expansion = await discoveryLogic.expandMapCluster(
        cluster,
        zoom: _zoom,
        filter: _filter,
        localFoodId: _activePinFoodId,
        // The same search half the badge was drawn with. Without it the probe
        // asks about a smaller set and answers with a zoom that does not split
        // this badge - tap, zoom, badge still there.
        search: _searchSelection,
      );

      if (expansion.splits) {
        _collapseExpandedCluster();
        _rebuildVisibleMarkers();
        _requestCamera(
          cluster.latitude,
          cluster.longitude,
          _clampZoom(expansion.splitZoom!),
        );
        return;
      }

      // Nothing left to zoom into. Draw the members themselves rather than a
      // badge that can never be opened.
      if (expansion.members.isNotEmpty) {
        _expandedCluster = cluster;
        _expandedPins = expansion.members;
        _rebuildVisibleMarkers();
        _paintedSignature = _markerSignature();
        safeNotifyListeners();
      }
      _requestCamera(
        cluster.latitude,
        cluster.longitude,
        DiscoveryLogicFacade.maximumZoom,
      );
    } finally {
      _clusterOpening = false;
    }
  }

  /// One tap at a time - a second tap while the first is still being answered
  /// would race the camera.
  bool _clusterOpening = false;

  /// Records what the keyword is asking the map about, and reloads if that
  /// changed. One request, the same one the filter uses.
  ///
  /// The comparison matters: `_runSearch` fires on every debounced keystroke,
  /// and a keyword whose *matches* have not changed - another character typed
  /// into a word that already resolved - must not refetch the map.
  void _applySearchSelection(ExplorationSearchResults results) {
    _searchLayerFor = results;
    final MapSearchSelection next = discoveryLogic.searchSelection(results);
    if (next.cacheKey == _searchSelection.cacheKey) return;
    _searchSelection = next;
    // An open cluster belonged to the old answer; it is stale now.
    _collapseExpandedCluster();
    if (isDetailedView) _loadPins();
  }

  /// Forgets the keyword's half of the marker query, and puts the map back to
  /// what the filters alone say. Nothing is "restored": the filtered markers
  /// were never replaced, they were only joined.
  void _clearSearchSelection() {
    _searchLayerFor = ExplorationSearchResults.empty;
    if (_searchSelection.isEmpty) return;
    _searchSelection = MapSearchSelection.none;
    _collapseExpandedCluster();
    if (isDetailedView) _loadPins();
  }

  /// A11.1 - tap the map outside the overlay, or swipe it down.
  void dismissPin() {
    if (_selectedPin == null) return;
    _pinDetailRevision++;
    _pinDetailLoading = false;
    _selectedPin = null;
    // Drops the marker again if it was only on the map because it was open.
    _rebuildVisibleMarkers();
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
    if (!_locationPermissionGranted) {
      _notice = 'Location permission is required to use Quick Mode.';
      safeNotifyListeners();
      return;
    }
    if (!_sharedLocation.isKnown) {
      _notice =
          'Could not get your location. Check that GPS is switched on, '
          'then try Quick Mode again.';
      safeNotifyListeners();
      return;
    }
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
    // The Filter pill closes the panel it opened, and that is a way out without
    // applying - so it cancels, exactly as the Cancel button does.
    if (_filterPanelOpen) {
      cancelFilter();
      return;
    }
    _draftFilter = _filter;
    _filterPanelOpen = true;
    safeNotifyListeners();
  }

  void toggleGroupExpanded(ExplorationFilterGroup group) {
    if (!_expandedGroups.remove(group)) _expandedGroups.add(group);
    safeNotifyListeners();
  }

  /// A7-3 - tick or untick one option. A group holds as many as are ticked.
  ///
  /// Draft only. Nothing is recalculated (REQ102_28) or redrawn (REQ102_29)
  /// until [applyFilter]; the chip just changes colour.
  void toggleFilterOption(ExplorationFilterGroup group, String option) {
    final Set<String> chosen = <String>{..._draftFilter.selectionFor(group)};
    if (!chosen.remove(option)) chosen.add(option);
    _setDraftGroup(group, chosen);
  }

  /// The "All" chip at the head of a filter row - untick the whole group.
  void clearFilterGroup(ExplorationFilterGroup group) {
    if (_draftFilter.selectionFor(group).isEmpty) return;
    _setDraftGroup(group, const <String>{});
  }

  void _setDraftGroup(ExplorationFilterGroup group, Set<String> options) {
    final Set<String> chosen = Set<String>.unmodifiable(options);
    // Built field by field rather than through a copyWith, because copyWith
    // cannot tell "leave this alone" from "clear this group".
    _draftFilter = ExplorationFilter(
      meals: group == ExplorationFilterGroup.meal ? chosen : _draftFilter.meals,
      categories: group == ExplorationFilterGroup.category
          ? chosen
          : _draftFilter.categories,
      tastes: group == ExplorationFilterGroup.taste
          ? chosen
          : _draftFilter.tastes,
      types: group == ExplorationFilterGroup.type ? chosen : _draftFilter.types,
    );
    safeNotifyListeners();
  }

  /// A7-4 - Apply. The one place a filter change reaches the map.
  ///
  /// One reload for however many chips were ticked, and none at all when the
  /// panel is closed exactly as it was opened - Apply on an untouched panel is
  /// a question the map has already answered.
  void applyFilter() {
    final bool changed = filterDraftChanged;
    _filter = _draftFilter;
    _filterPanelOpen = false;
    safeNotifyListeners();
    if (changed) _reloadActiveView();
  }

  /// A7-5 - Cancel, or any other way out of the panel: the chips ticked since
  /// it opened are dropped and the active filter stands, untouched.
  void cancelFilter() {
    _draftFilter = _filter;
    _filterPanelOpen = false;
    safeNotifyListeners();
  }

  /// Set equality, four groups of it. `==` on two `Set`s is identity, so the
  /// draft would always read as changed without this.
  static bool _sameFilter(ExplorationFilter a, ExplorationFilter b) =>
      ExplorationFilterGroup.values.every((ExplorationFilterGroup group) {
        final Set<String> left = a.selectionFor(group);
        final Set<String> right = b.selectionFor(group);
        return left.length == right.length && left.containsAll(right);
      });

  // ===========================================================================
  // Search (A8)
  // ===========================================================================

  void openSearchPanel() {
    _searchPanelOpen = true;
    safeNotifyListeners();

    // **Pointing at a field that still holds a keyword brings its suggestions
    // back.** Picking a result clears the result list but leaves the text, so
    // tapping the field again used to open an empty panel and sit there until
    // another character was typed. Nothing here re-runs a search that already
    // has an answer - including "no matches", which is an answer.
    if (_searchKeyword.trim().isEmpty) return;
    if (_searching || _searchMessage != null) return;
    if (_searchResults.places.isNotEmpty || _searchResults.foods.isNotEmpty) {
      return;
    }
    submitSearch(_searchKeyword);
  }

  /// The keyboard's Search key (A8-1).
  ///
  /// Runs the search **now**, with whatever the field already holds. The field
  /// asked for that key with `TextInputAction.search` but had nothing wired to
  /// it, so pressing it did nothing: the only way to get results out of text
  /// already in the box was to type another character and wait out the
  /// debounce. Submitting is an explicit request, so it skips the debounce
  /// rather than arming it.
  ///
  /// An empty field takes the same path as the clear button - close the panel
  /// and put the map back - which is the existing answer to "no keyword", and
  /// is visible, rather than firing a query for an empty string.
  void submitSearch(String keyword) {
    _searchDebounce?.cancel();

    if (keyword.trim().isEmpty) {
      clearSearch();
      return;
    }

    _searchKeyword = keyword;
    _searchMessage = null;
    _searchPanelOpen = true;
    _searching = true;
    // A8 - the keyword takes the map, so the Target Frame gives it back.
    _suspendSwipeModeForSearch();
    safeNotifyListeners();
    _runSearch(keyword, ++_searchRevision);
  }

  /// A8-1 / A8-2 / A8-3 - one keyword, matched against locations and food.
  ///
  /// **Debounced.** This is wired straight to the field's `onChanged`, so it
  /// used to run a full search on every keystroke - typing "kuala lumpur" was
  /// twelve searches, of which eleven were thrown away, each one walking the
  /// place index and querying the food catalogue. Now the keystroke only
  /// records the text and arms a timer; the search runs once the typing stops.
  ///
  /// The search itself, and its results, are unchanged.
  void updateSearchKeyword(String keyword) {
    _searchKeyword = keyword;
    _searchMessage = null;
    _searchDebounce?.cancel();

    if (keyword.trim().isEmpty) {
      _searchRevision++;
      _searchResults = ExplorationSearchResults.empty;
      _searching = false;
      // Emptying the field is clearing the search: the keyword stops being part
      // of the marker query and what is left is the filtered map - which is
      // what it was all along, since the keyword only ever joined it.
      _clearSearchSelection();
      // The keyword is gone, so Swipe Mode can have the map back.
      _resumeSwipeModeAfterSearch();
      safeNotifyListeners();
      return;
    }

    _searchPanelOpen = true;
    _searching = true;
    // Only the first keystroke does anything here; the rest return early.
    _suspendSwipeModeForSearch();
    safeNotifyListeners();

    final int revision = ++_searchRevision;
    _searchDebounce = Timer(
      _searchDebounceDelay,
      () => _runSearch(keyword, revision),
    );
  }

  Future<void> _runSearch(String keyword, int revision) async {
    try {
      final ExplorationSearchResults results = await discoveryLogic
          .searchExploration(keyword);
      // Two guards, because there are two ways to be stale: a newer keystroke
      // started a newer search, and a late reply for a keyword the tourist has
      // already changed.
      if (revision != _searchRevision) return;
      if (results.keyword != _searchKeyword.trim()) return;

      _searchResults = results;
      // A8.2 - no location entry and no local food entry matched.
      _searchMessage = results.places.isEmpty && results.foods.isEmpty
          ? noResultMessage
          : null;

      // The same answer fills two things: the result list, and the markers the
      // keyword adds to the map. They are filled together and cleared apart.
      _applySearchSelection(results);
    } catch (error, stackTrace) {
      if (revision != _searchRevision) return;
      setError(error, stackTrace);
    } finally {
      if (revision == _searchRevision) {
        _searching = false;
        safeNotifyListeners();
      }
    }
  }

  Timer? _searchDebounce;
  int _searchRevision = 0;

  /// Long enough to swallow a burst of typing, short enough that the results
  /// feel immediate once the fingers stop.
  static const Duration _searchDebounceDelay = Duration(milliseconds: 250);

  /// A8-4 / REQ102_22 - centre and zoom on the chosen state, city or location.
  ///
  /// **A restaurant or landmark result opens itself.** Somebody who typed a
  /// restaurant's name and picked it out of the list has already told the app
  /// which place they mean; landing them on a map covered in pins and leaving
  /// them to find it again is asking the same question twice. The camera goes
  /// to it and its detail sheet opens, exactly as if the pin had been tapped.
  ///
  /// The sheet is opened from what the search result carries - name and
  /// position - and `selectPin` fills in the rest by id, which is the same
  /// two-stage load a tapped marker uses.
  void selectPlace(PlaceSuggestion place) {
    _searchPanelOpen = false;
    _searchKeyword = place.name;
    _searchResults = ExplorationSearchResults.empty;
    _searchMessage = null;
    _requestCamera(place.latitude, place.longitude, place.zoom);

    if (!place.isPlaceOnTheMap) {
      // A state, city, town or area: there is no single place to open.
      dismissPin();
      return;
    }

    selectPin(
      MapPin(
        referenceId: place.referenceId!,
        kind: place.isRestaurant ? MapPinKind.restaurant : MapPinKind.landmark,
        latitude: place.latitude,
        longitude: place.longitude,
        label: place.name,
        weight: 1,
      ),
    );
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

    // The dish narrows the **heatmap** (REQ102_33) and adds a **layer** to the
    // detailed map - it no longer replaces the pins the filter chips are
    // drawing. Picking "Nasi Lemak" out of the results should show where nasi
    // lemak is, on top of the map the tourist already had, not instead of it.
    _applySearchSelection(
      ExplorationSearchResults(
        keyword: food.name,
        places: const <PlaceSuggestion>[],
        foods: <LocalFood>[food],
      ),
    );
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
    _searchDebounce?.cancel();
    _searchRevision++;
    final bool hadFood = _selectedFood != null;
    _searchKeyword = '';
    _searchResults = ExplorationSearchResults.empty;
    _searchMessage = null;
    _searchPanelOpen = false;
    _targetFrameOwnsSelection = false;
    _selectedFood = null;
    // The keyword leaves the marker query and the filtered markers remain.
    // Nothing is "restored": they were never replaced, only joined.
    _clearSearchSelection();
    // The bar comes back, with the deck it had before the search.
    _resumeSwipeModeAfterSearch();
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
    // Tapping the map is a way out of the filter panel, and a way out without
    // applying keeps the filter the map already has.
    if (_filterPanelOpen) cancelFilter();

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
        origin: _sharedLocation,
      );

  /// Matches edits the same device-local Swipe session. Reload it when that
  /// page closes so this in-memory Dashboard copy cannot overwrite a removed
  /// like the next time the tourist moves or likes a card.
  Future<void> refreshSwipeSessionAfterMatches() async {
    final SwipeModePreparation? preparation = _swipePreparation;
    if (preparation == null) return;
    await _runSwipeCommand(() async {
      final SwipeSession? refreshed = await discoveryLogic.reloadSwipeSession(
        preparation,
      );
      if (refreshed != null) _swipeSession = refreshed;
      _showSwipeResumePrompt = false;
      _swipeLikeRevision++;
    }, showLoading: false);
  }

  /// Opens Profile and applies saved preference or dietary changes when the
  /// tourist returns to this still-mounted Dashboard.
  Future<void> openProfile() async {
    final bool changed =
        await AppNavigator.push<bool>(AppRoutes.profile) ?? false;
    if (!changed || !isDetailedView || _swipePreparation == null) return;
    _swipeQueueUpdatePending = true;
    _swipeQueueProfileChanged = true;
    safeNotifyListeners();
  }

  Future<void> applySwipeQueueUpdate() async {
    final bool rebuildWholeQueue = _swipeQueueProfileChanged;
    _swipeQueueUpdatePending = false;
    _swipeQueueProfileChanged = false;
    safeNotifyListeners();
    await refreshSwipeQueueAfterProfileChange(
      rebuildWholeQueue: rebuildWholeQueue,
    );
  }

  void dismissSwipeQueueUpdate() {
    if (!_swipeQueueUpdatePending) return;
    _swipeQueueUpdatePending = false;
    _swipeQueueProfileChanged = false;
    safeNotifyListeners();
  }

  /// Re-reads preferences and restrictions, then reconciles the active local
  /// Swipe session without reopening its Continue/New prompt.
  Future<void> refreshSwipeQueueAfterProfileChange({
    bool rebuildWholeQueue = false,
  }) async {
    if (!isDetailedView || _swipePreparation == null) return;

    final bool wasShowingResumePrompt = _showSwipeResumePrompt;
    final int? previousFoodId = currentSwipeFood?.id;
    await _runSwipeCommand(() async {
      final SwipeModePreparation refreshed = await discoveryLogic
          .refreshSwipeModeAfterProfileChange(
            latitude: _centreLatitude,
            longitude: _centreLongitude,
            distanceOrigin: _sharedLocation,
            rebuildWholeQueue: rebuildWholeQueue,
            south: _swipeViewportSouth,
            west: _swipeViewportWest,
            north: _swipeViewportNorth,
            east: _swipeViewportEast,
          );
      _swipePreparation = refreshed;
      _rememberSwipeQueueViewport();

      if (wasShowingResumePrompt) {
        _swipeSession = null;
        _showSwipeResumePrompt = refreshed.savedSession != null;
        if (!_showSwipeResumePrompt) {
          _swipeSession = await discoveryLogic.startNewSwipeSession(refreshed);
        }
      } else {
        _swipeSession = refreshed.savedSession;
        _showSwipeResumePrompt = false;
        _swipeSession ??= await discoveryLogic.startNewSwipeSession(refreshed);
      }

      if (_swipePanelExpanded && !_showSwipeResumePrompt) {
        final LocalFood? refreshedFood = currentSwipeFood;
        if (refreshedFood?.id != previousFoodId) {
          showFoodInTargetFrame(refreshedFood);
        }
      }
    });
  }

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
  double? _swipeViewportSouth;
  double? _swipeViewportWest;
  double? _swipeViewportNorth;
  double? _swipeViewportEast;

  double? _lastPinLatitude;
  double? _lastPinLongitude;
  double? _lastPinZoom;

  Timer? _pinRefreshTimer;

  /// Ceiling on one Find Me attempt, a little above the device layer's own so
  /// that layer gets to answer first when it can.
  static const Duration _locateTimeout = Duration(seconds: 16);

  /// How long the map has to sit still before the pins are refetched. Short
  /// enough to feel immediate, long enough that one pinch is one query.
  static const Duration _pinRefreshDelay = Duration(milliseconds: 350);

  /// Degrees of travel that justify refetching the pins for a new viewport.
  static const double _pinRefreshDelta = 0.05;

  /// Zoom change that justifies the same. A tenth of a level is below what
  /// anyone can pinch deliberately, so in practice any real zoom refetches.
  static const double _pinRefreshZoomDelta = 0.1;

  /// What a filter change or a food search triggers: the previous answer is
  /// stale, so the pins go before the new query runs.
  Future<void> _reloadActiveView() =>
      isHeatmapView ? _loadHeatmap() : _loadPins();

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
    // Nothing to prepare for a bar that is not on screen - and this is the
    // most expensive call in the module, so it is worth not making. The queue
    // is built lazily when the bar is expanded, which is the path a tourist
    // takes after clearing the search.
    if (hasActiveSearch) return;
    final int revision = ++_swipePrepareRevision;
    _swipeLoading = true;
    _swipeError = null;
    safeNotifyListeners();
    try {
      final SwipeModePreparation preparation = await discoveryLogic
          .prepareSwipeMode(
            latitude: _centreLatitude,
            longitude: _centreLongitude,
            distanceOrigin: _sharedLocation,
            south: _swipeViewportSouth,
            west: _swipeViewportWest,
            north: _swipeViewportNorth,
            east: _swipeViewportEast,
          );
      if (revision != _swipePrepareRevision || !isDetailedView) return;
      _swipePreparation = preparation;
      _rememberSwipeQueueViewport();
      _swipeQueueUpdatePending = false;
      _swipeQueueProfileChanged = false;
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

  void _rememberSwipeQueueViewport() {
    _swipeQueueSouth = _swipeViewportSouth;
    _swipeQueueWest = _swipeViewportWest;
    _swipeQueueNorth = _swipeViewportNorth;
    _swipeQueueEast = _swipeViewportEast;
  }

  void _offerSwipeQueueUpdateIfViewportChanged() {
    if (_swipePreparation == null || !_hasSwipeViewportBounds) return;
    const double tolerance = 0.001;
    final bool changed =
        _swipeQueueSouth == null ||
        (_swipeViewportSouth! - _swipeQueueSouth!).abs() > tolerance ||
        (_swipeViewportWest! - _swipeQueueWest!).abs() > tolerance ||
        (_swipeViewportNorth! - _swipeQueueNorth!).abs() > tolerance ||
        (_swipeViewportEast! - _swipeQueueEast!).abs() > tolerance;
    if (!changed || _swipeQueueUpdatePending) return;
    _swipeQueueUpdatePending = true;
    _swipeQueueProfileChanged = false;
    safeNotifyListeners();
  }

  bool get _hasSwipeViewportBounds =>
      _swipeViewportSouth != null &&
      _swipeViewportWest != null &&
      _swipeViewportNorth != null &&
      _swipeViewportEast != null;

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

  /// A keyword has taken the map, so Swipe Mode stands down (A8).
  ///
  /// **Collapse, not teardown.** [_leaveSwipeModeForHeatmap] throws the
  /// preparation and the session away, which is right when the tourist leaves
  /// the detailed view - but rebuilding them costs the largest read in the
  /// application, and a search is a detour, not a departure. The deck, its
  /// likes and its state binding all survive; the panel closes and the Target
  /// Frame lets go of the map.
  void _suspendSwipeModeForSearch() {
    if (!_swipePanelExpanded) return;
    // True only when the frame was actually narrowing the markers - an open
    // panel with no card yet was not, and needs no reload.
    final bool heldTheMap = _targetFrameOwnsSelection && _selectedFood != null;

    _swipePanelExpanded = false;
    // The prompt belonged to a deck that is no longer on screen.
    _swipeQueueUpdatePending = false;
    _swipeQueueProfileChanged = false;
    if (_targetFrameOwnsSelection) {
      _selectedFood = null;
      _targetFrameOwnsSelection = false;
    }
    // Said out loud, because a panel that vanishes mid-swipe otherwise reads
    // as lost work. Nothing is lost - the deck and its likes are still here.
    _notice = swipePausedNotice;
    // `_activePinFoodId` has just become null, so the markers the frame was
    // narrowing must be asked for again. `_applySearchSelection` cannot be
    // relied on to do it: a keyword that matches nothing changes no selection
    // and triggers no load, and the map would keep one dish's pins under a
    // search asking about something else.
    if (heldTheMap) _reloadActiveView();
  }

  /// The keyword is gone and the Discovery Layer Bar is back (A8.3).
  ///
  /// One thing can have gone stale while the bar was hidden: which state the
  /// deck belongs to. `_schedulePinRefresh` skips its region check during a
  /// search, so a tourist who panned into another state while searching would
  /// otherwise reopen the bar on the previous state's queue. This is one
  /// cached `regionAt`, and it re-prepares only when the state really changed.
  void _resumeSwipeModeAfterSearch() {
    // The banner explained a bar that is back on screen; leaving it up would
    // make it a lie. Compared rather than cleared outright, so a location or
    // navigation notice raised since is not swallowed.
    if (_notice == swipePausedNotice) _notice = null;
    if (!isDetailedView || _swipePreparation == null) return;
    _refreshSwipeModeRegion();
  }

  void _leaveSwipeModeForHeatmap() {
    _swipePrepareRevision++;
    _swipePanelExpanded = false;
    _swipePreparation = null;
    _swipeSession = null;
    _swipeLoading = false;
    _swipeError = null;
    _showSwipeResumePrompt = false;
    _swipeQueueUpdatePending = false;
    _swipeQueueProfileChanged = false;
    _swipeQueueSouth = null;
    _swipeQueueWest = null;
    _swipeQueueNorth = null;
    _swipeQueueEast = null;
    if (_targetFrameOwnsSelection) {
      _selectedFood = null;
      _targetFrameOwnsSelection = false;
    }
  }

  Future<void> _loadHeatmap() => runGuarded(() async {
    _pinLoadRevision++;
    // Leaving the detailed view invalidates its pins. The keyword's half of
    // the query is *not* forgotten - it is remembered on `_searchSelection`, so
    // coming back down asks the one question again with the search still in it.
    if (_pins.isNotEmpty || _clusters.isNotEmpty) {
      _pins = const <MapPin>[];
      _clusters = const <MapCluster>[];
      _collapseExpandedCluster();
      _rebuildVisibleMarkers();
      _pinsInView = 0;
      _pinLimit = 0;
      _regionInView = null;
      _paintedSignature = _markerSignature();
      safeNotifyListeners();
    }
    _distribution = await discoveryLogic.foodDistribution(
      filter: _filter,
      localFoodId: _selectedFood?.id,
    );

    // **The heatmap only recolours when this fires.** `runGuarded(silent: true)`
    // deliberately does not notify, and `silent` is true whenever the heatmap
    // already has scores - which is every load after the first. So a new
    // distribution was assigned and nobody was told: pressing Apply changed the
    // filter, closed the panel and fetched new scores, and the old colours
    // stayed on screen until something unrelated happened to notify.
    //
    // `_loadPins` carries the same note about the same omission. This is its
    // twin, and it went unnoticed for longer because a filter tap used to
    // notify on its own way through - batching the filter behind Apply took
    // that accident away and left the bug visible.
    //
    // Skipped when the answer is identical to what is already painted, which is
    // the common case when a filter is applied and then re-applied unchanged:
    // the whole dashboard is one `Consumer`, so a needless notify rebuilds the
    // map, the panels and every marker.
    final String signature = _distributionSignature();
    if (signature == _paintedDistribution) return;
    _paintedDistribution = signature;
    safeNotifyListeners();
  }, silent: _distribution.regions.isNotEmpty);

  /// Loads pins for the current map viewport.
  ///
  /// [clearFirst] removes stale pins immediately when the filter or selected
  /// food changes. During ordinary panning and zooming, the existing pins stay
  /// visible until their replacements arrive to avoid map flicker.
  ///
  /// The revision check prevents a slower request for an older Swipe card from
  /// replacing the locations for the food currently in the Target Frame.
  Future<void> _loadPins({bool clearFirst = false}) => runGuarded(() async {
    final int revision = ++_pinLoadRevision;
    final int? requestedFoodId = _activePinFoodId;
    final bool useSwipeViewport =
        requestedFoodId != null && _hasSwipeViewportBounds;

    if (clearFirst && (_pins.isNotEmpty || _clusters.isNotEmpty)) {
      _pins = const <MapPin>[];
      _clusters = const <MapCluster>[];
      // A new filter or dish is a different question; an opened cluster from
      // the old one no longer belongs on the map.
      _collapseExpandedCluster();
      _rebuildVisibleMarkers();
      _pinsInView = 0;
      _pinLimit = 0;
      _paintedSignature = _markerSignature();
      safeNotifyListeners();
    }

    _lastPinLatitude = _centreLatitude;
    _lastPinLongitude = _centreLongitude;
    _lastPinZoom = _zoom;
    // The viewport and the food go to Postgres; what comes back is what is
    // drawn. The zoom decides both the shape of the answer - cluster counts or
    // individual pins - and how many of them.
    final MapPinPage page = await discoveryLogic.mapPins(
      filter: _filter,
      localFoodId: requestedFoodId,
      south: useSwipeViewport ? _swipeViewportSouth : _viewportSouth,
      west: useSwipeViewport ? _swipeViewportWest : _viewportWest,
      north: useSwipeViewport ? _swipeViewportNorth : _viewportNorth,
      east: useSwipeViewport ? _swipeViewportEast : _viewportEast,
      fromLatitude: _sharedLocation.isKnown ? _sharedLocation.latitude : null,
      fromLongitude: _sharedLocation.isKnown ? _sharedLocation.longitude : null,
      zoom: _zoom,
      // The keyword's half of the same question. Empty while no search is
      // active, and the query is then exactly the one it has always been.
      search: _searchSelection,
    );
    // REQ103 - the race guard. Swiping Nasi Lemak -> Laksa -> Satay fires
    // three loads; the first two must not land on top of the third. The
    // revision covers "a newer load started", the food check covers "the Target
    // Frame moved on while this one was in flight".
    if (revision != _pinLoadRevision || requestedFoodId != _activePinFoodId) {
      return;
    }
    _pins = page.pins;
    _clusters = page.clusters;
    _pinsInView = page.totalInView;
    _pinLimit = page.limit;
    _rebuildVisibleMarkers();
    await _refreshRegionInView(revision);

    // **The map only redraws when this fires.** `runGuarded(silent: true)`
    // deliberately does not notify, and for a long time neither did this - so
    // new markers were assigned and never painted, and the map updated only
    // when something unrelated happened to notify. That is what made tapping a
    // cluster look like it did nothing.
    //
    // Skipped when the answer is identical to what is already on screen, which
    // is the common case when panning back over ground already visited: the
    // whole dashboard is one `Consumer`, so a needless notify rebuilds the map,
    // the panels and every marker.
    final String signature = _markerSignature();
    if (signature == _paintedSignature) return;
    _paintedSignature = signature;
    safeNotifyListeners();
  }, silent: true);

  /// Exactly what is on screen, so an unchanged answer can skip the rebuild.
  /// Built from every id and count rather than a length, because two different
  /// sets of the same size must not compare equal.
  String _markerSignature() {
    final StringBuffer buffer = StringBuffer();
    for (final MapPin pin in _visiblePins) {
      buffer
        ..write(pin.kind.name)
        ..write(pin.referenceId)
        // Whether it is ringed as a search result is part of what is drawn. A
        // place already on the filtered map that the keyword then matches is
        // the same id in the same place and would otherwise compare equal, so
        // the ring would never be painted.
        ..write(pin.isSearchResult ? '*' : '')
        ..write(',');
    }
    buffer.write('|');
    for (final MapCluster cluster in _visibleClusters) {
      buffer
        ..write(cluster.key)
        ..write('x')
        ..write(cluster.count)
        // The proportion of search results decides the badge's colour, so two
        // cells with the same count but different make-up are not the same
        // picture. Left out, a keyword would recolour nothing.
        ..write('s')
        ..write(cluster.searchCount)
        ..write(',');
    }
    return buffer.toString();
  }

  String _paintedSignature = '';

  /// Exactly what the heatmap paints, so an unchanged answer can skip the
  /// rebuild. Sixteen states of counts are far cheaper to compare than a
  /// needless repaint of the map, the panels and every marker.
  ///
  /// Built from the counts rather than the score, because the score is a
  /// double derived from them: two different tallies that happen to round to
  /// the same ratio are still two different maps, and the state cards show the
  /// numbers themselves.
  String _distributionSignature() {
    final StringBuffer buffer = StringBuffer()
      ..write(_distribution.maximumPlaceCount)
      ..write('/')
      ..write(_distribution.matchingFoodCount)
      ..write('|');
    for (final RegionAvailability region in _distribution.regions) {
      buffer
        ..write(region.region.code)
        ..write(':')
        ..write(region.placeCount)
        ..write('x')
        ..write(region.foodCount)
        ..write(',');
    }
    return buffer.toString();
  }

  String _paintedDistribution = '';

  /// Reads the state under the middle of the map out of the heatmap tally.
  ///
  /// Costs nothing beyond a point-in-polygon test: `_distribution` was already
  /// computed for the heatmap, and the region catalogue is cached.
  Future<void> _refreshRegionInView(int revision) async {
    final Region? region = await discoveryLogic.regionAt(
      _centreLatitude,
      _centreLongitude,
    );
    if (revision != _pinLoadRevision) return;
    if (region == null) {
      _regionInView = null;
      return;
    }
    for (final RegionAvailability availability in _distribution.regions) {
      if (availability.region.code == region.code) {
        _regionInView = availability;
        return;
      }
    }
    _regionInView = null;
  }

  /// The dish the **base** pins are narrowed to, which is only ever the one in
  /// Swipe Mode's Target Frame.
  ///
  /// A dish picked out of the search results used to narrow these too, which
  /// meant searching threw the filtered map away. It now arrives as a search
  /// layer on top instead, so the chips keep their answer and the keyword gets
  /// its own. Swipe Mode is unchanged: it owns the map while its panel is open,
  /// which is the whole point of a Target Frame.
  int? get _activePinFoodId => _targetFrameOwnsSelection && _swipePanelExpanded
      ? _selectedFood?.id
      : null;

  // ---------------------------------------------------------------------------
  // Search and the markers
  // ---------------------------------------------------------------------------
  //
  // There is nothing here to load. A keyword changes one input to the marker
  // query - `_searchSelection` - and `_loadPins` asks the one question that
  // answers for the filtered map and the search together. What used to be a
  // second fetch, a second pin list, a second cluster list, a second revision
  // counter and a second repaint is `_applySearchSelection` and
  // `_clearSearchSelection`, above.

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
      _rebuildVisibleMarkers();
      // Put the illustration back to its resting scale, so returning to the
      // overview never lands on a half-pinched canvas.
      if (next == DashboardMapMode.heatmap) {
        _heatmapResetToken++;
        _heatmapScale = 1;
        _leaveSwipeModeForHeatmap();
      }
    }

    safeNotifyListeners();

    if (changed) {
      if (next == DashboardMapMode.detailed) {
        // Deliberately **not** loading pins here. The viewport bounds are only
        // known once the map widget reports the move back through
        // `onCameraChanged`; loading now would query the previous - often
        // country-sized - box at the new zoom and flash several hundred markers
        // in the wrong places before the correct answer replaced them. Every
        // other camera command already relies on that callback.
        _prepareSwipeModeForActiveState();
      } else {
        // The heatmap is painted, not a slippy map, so nothing reports back
        // for it.
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
