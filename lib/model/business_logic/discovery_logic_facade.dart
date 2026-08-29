import '../../domain_model/exploration_filter.dart';
import '../../domain_model/exploration_search.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/map.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/tourist_location.dart';
import 'food_discovery_logic.dart';
import 'map_exploration_logic.dart';
import 'restaurant_discovery_logic.dart';

/// Finding food in the real world: restaurants, menus, photo recognition and
/// the dashboard map. Used by the Dashboard, RestaurantRecommendation,
/// RestaurantDetail, RestaurantItemList and FoodRecognition ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class DiscoveryLogicFacade {
  DiscoveryLogicFacade();

  final RestaurantDiscoveryLogic restaurantDiscovery =
      RestaurantDiscoveryLogic();
  final FoodDiscoveryLogic foodDiscovery = FoodDiscoveryLogic();
  final MapExplorationLogic mapExploration = MapExplorationLogic();

  // ---------------------------------------------------------------------------
  // Dev GPS mock (Android-only presenter tool), re-exposed flat.
  // ---------------------------------------------------------------------------

  /// Whether this build can mock the OS GPS (Android, non-web). Views hide the
  /// dev control when false.
  bool get mockGpsSupported => mapExploration.mockGpsSupported;

  /// Whether a mock is live right now.
  bool get mockGpsActive => mapExploration.mockGpsActive;

  /// Teleports the OS GPS to [latitude]/[longitude]. Returns an error message,
  /// or null on success.
  Future<String?> setMockGps({
    required double latitude,
    required double longitude,
  }) => mapExploration.setMockGps(latitude: latitude, longitude: longitude);

  /// Stops mocking and resumes real GPS fixes.
  Future<void> stopMockGps() => mapExploration.stopMockGps();

  Future<List<Restaurant>> getQuickModeRestaurants({
    required TouristLocation location,
    required int limit,
  }) => restaurantDiscovery.nearbyWithAutomaticExpansion(
    location: location,
    limit: limit,
  );

  // ===========================================================================
  // REQ102 - the Local Food Dashboard.
  //
  // `DashboardViewModel` calls these, never `facade.mapExploration.xxx`, and
  // never `MapExplorationLogic` itself.
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Map geometry, re-exposed.
  //
  // A ViewModel knows this facade and nothing below it, so it must not reach
  // into `MapExplorationLogic` for a constant either. `MapExplorationLogic`
  // stays the single place these values are decided; the facade only forwards
  // them, exactly as it forwards the methods.
  // ---------------------------------------------------------------------------

  /// REQ102_1 - the box the camera is clamped to.
  static const double malaysiaSouth = MapExplorationLogic.malaysiaSouth;
  static const double malaysiaWest = MapExplorationLogic.malaysiaWest;
  static const double malaysiaNorth = MapExplorationLogic.malaysiaNorth;
  static const double malaysiaEast = MapExplorationLogic.malaysiaEast;

  /// REQ102_14 - the whole-country overview.
  static const double malaysiaCentreLatitude =
      MapExplorationLogic.malaysiaCentreLatitude;
  static const double malaysiaCentreLongitude =
      MapExplorationLogic.malaysiaCentreLongitude;
  static const double malaysiaOverviewZoom =
      MapExplorationLogic.malaysiaOverviewZoom;

  /// REQ102_12 / REQ102_13 - "the predefined zoom level".
  static const double detailedViewZoom = MapExplorationLogic.detailedViewZoom;

  /// REQ102_12 - the predefined level as a heatmap-canvas scale factor.
  static const double heatmapDetailScale =
      MapExplorationLogic.heatmapDetailScale;

  /// REQ102_8 / REQ102_9 - where a GPS fix settles the map.
  static const double currentLocationZoom =
      MapExplorationLogic.currentLocationZoom;

  static const double minimumZoom = MapExplorationLogic.minimumZoom;
  static const double maximumZoom = MapExplorationLogic.maximumZoom;

  /// REQ102_3 / REQ102_5 - one press of "+" or "-".
  static const double zoomStep = MapExplorationLogic.zoomStep;

  /// REQ102_24 - REQ102_27 - the options in one Smart Filtering group.
  List<String> filterOptions(ExplorationFilterGroup group) =>
      mapExploration.optionsFor(group);

  /// The label on the pill that opens a filter row.
  String filterLabel(ExplorationFilterGroup group) =>
      mapExploration.labelFor(group);

  /// Above this the country mask comes off (see `MapExplorationLogic`).
  static const double countryMaskMaxZoom =
      MapExplorationLogic.countryMaskMaxZoom;

  /// REQ102_1 - every Malaysian state, with its outline.
  Future<List<Region>> regions() => mapExploration.regions();

  /// Drops the cached map data so the next read is fresh - what the dashboard
  /// calls when the tourist accepts the update prompt.
  void clearMapCache() => mapExploration.clearMapCache();

  /// REQ102_1 - the tight coastline, which the painted overview clips to.
  Future<List<CountryOutline>> countryOutlines() => mapExploration.outlines();

  /// REQ102_1 - the generous rings the detailed map masks with.
  Future<List<CountryOutline>> countryMaskOutlines() =>
      mapExploration.maskOutlines();

  /// The state a coordinate falls in, or null when it is outside Malaysia.
  Future<Region?> regionAt(double latitude, double longitude) =>
      mapExploration.regionAt(latitude, longitude);

  /// REQ102_8 / REQ102_14 - whether the dashboard may centre on this fix.
  Future<bool> isWithinMalaysia(double latitude, double longitude) =>
      mapExploration.isWithinMalaysia(latitude, longitude);

  /// REQ102_15 / REQ102_28 - the whole heatmap for one filter selection.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame, or null to score every food (REQ102_33).
  Future<FoodDistribution> foodDistribution({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
  }) => mapExploration.distribution(filter: filter, localFoodId: localFoodId);

  /// REQ102_32 - restaurant and submitted-landmark pins for the detailed map.
  ///
  /// **The facade door for REQ103_8.** Swipe Mode does not call this directly -
  /// it calls `DashboardViewModel.showFoodInTargetFrame`, which lands here.
  ///
  /// @param localFoodId (swipe mode) - `LocalFood.id` of the dish in the
  ///        Target Frame; only places serving it are pinned. Null pins every
  ///        place serving anything that survives the filter.
  Future<List<MapPin>> mapPins({
    ExplorationFilter filter = ExplorationFilter.none,
    int? localFoodId,
    double? south,
    double? west,
    double? north,
    double? east,
    double? fromLatitude,
    double? fromLongitude,
  }) => mapExploration.pins(
    filter: filter,
    localFoodId: localFoodId,
    south: south,
    west: west,
    north: north,
    east: east,
    fromLatitude: fromLatitude,
    fromLongitude: fromLongitude,
  );

  /// A8 - one keyword against locations and the local-food catalogue.
  Future<ExplorationSearchResults> searchExploration(String keyword) =>
      mapExploration.search(keyword);

  /// REQ102_6 - request GPS permission (A1 / A2).
  Future<bool> ensureLocationPermission() =>
      mapExploration.ensureLocationPermission();

  /// REQ102_7 - one GPS fix.
  Future<TouristLocation> currentLocation() => mapExploration.currentLocation();
}
