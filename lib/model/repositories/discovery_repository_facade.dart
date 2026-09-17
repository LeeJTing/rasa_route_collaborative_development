import '../../domain_model/exploration_search.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/map.dart';
import '../../domain_model/map_data_stamp.dart';
import '../../domain_model/map_place.dart';
import '../../domain_model/origin_verification.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/swipe_session.dart';
import '../../domain_model/tourist_location.dart';
import '../data_models/food_analysis_response.dart';
import 'camera_repository.dart';
import 'landmark_discovery_repository.dart';
import 'location_repository.dart';
import 'map_repository.dart';
import 'recognition_repository.dart';
import 'restaurant_repository.dart';
import 'search_history_repository.dart';
import 'swipe_repository.dart';

/// Everything about finding food out in the world: restaurants, menus, photo
/// recognition, and the map the tourist finds them on.
///
/// `map` and `location` are also reachable through `LandmarkRepositoryFacade`.
/// That is the same "second door to the same data" arrangement that facade
/// already documents - every facade holds its own reference to the one
/// `APIManager` / `DeviceCapabilityManager` singleton, so this is not a
/// duplicate source. `MapExplorationLogic` needs them from here because the
/// dashboard sits behind `DiscoveryLogicFacade`, and per the guideline a logic
/// class holds one repository facade.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not five
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class DiscoveryRepositoryFacade {
  DiscoveryRepositoryFacade();

  final RestaurantRepository _restaurant = RestaurantRepository();
  final LandmarkDiscoveryRepository _landmark = LandmarkDiscoveryRepository();
  final RecognitionRepository _recognition = RecognitionRepository();
  final SwipeRepository _swipe = SwipeRepository();

  /// REQ102 - the Malaysian regions and the food occurrences plotted on them.
  final MapRepository _map = MapRepository();

  /// REQ102_6 / REQ102_7 - GPS permission and fixes.
  final LocationRepository _location = LocationRepository();

  /// REQ106_1 - the camera permission that gates photo capture on
  /// `FoodRecognitionView`.
  final CameraRepository _camera = CameraRepository();

  /// REQ102_104 - the recent keywords, on this device only. The one
  /// repository here that never reaches `APIManager`.
  final SearchHistoryRepository _searchHistory = SearchHistoryRepository();

  /// 3-step origin verification for a dish name (Option C gate) - three
  /// separately-framed Gemini questions, fail-closed.
  Future<OriginVerification> verifyDishOrigin(String dishName) =>
      _recognition.verifyDishOrigin(dishName);

  Future<bool> requestCameraPermission() => _camera.requestCameraPermission();

  Future<FoodAnalysisResponse> identifyFoodName(List<int> imageBytes) =>
      _recognition.identifyFoodName(imageBytes);

  Future<FoodAnalysis> analyzeFoodFull(
    List<int> imageBytes, {
    LocalFood? storedDish,
  }) => _recognition.analyzeFoodFull(imageBytes, storedDish: storedDish);

  Future<FoodAnalysis> analyzeFoodByName(
    List<int> imageBytes,
    String name, {
    LocalFood? storedDish,
  }) =>
      _recognition.analyzeFoodByName(imageBytes, name, storedDish: storedDish);

  Future<({bool isTypo, String correctedName})> checkTypedNameSpelling({
    required String typedName,
    required String observedFood,
  }) => _recognition.checkTypedNameSpelling(
    typedName: typedName,
    observedFood: observedFood,
  );

  Future<List<Restaurant>> getRestaurants() => _restaurant.getRestaurants();

  Future<List<Restaurant>> getRestaurantsNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) => _restaurant.getRestaurantsNear(
    latitude: latitude,
    longitude: longitude,
    maximumDistanceKm: maximumDistanceKm,
  );

  Future<List<Restaurant>> getRestaurantsByIds(List<int> restaurantIds) =>
      _restaurant.getRestaurantsByIds(restaurantIds);

  Future<List<RestaurantItem>> getRestaurantItemsByRestaurantIds(
    List<int> restaurantIds,
  ) => _restaurant.getRestaurantItemsByRestaurantIds(restaurantIds);

  Future<Restaurant?> getRestaurantById(int restaurantId) =>
      _restaurant.getRestaurantById(restaurantId);

  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) =>
      _landmark.getSubmittedLandmarkById(landmarkId);

  Future<void> reactivateRestaurantFromClosure(int restaurantId) =>
      _restaurant.reactivateRestaurantFromClosure(restaurantId);

  Future<List<Region>> malaysiaRegions() => _map.malaysiaRegions();

  Future<List<RegionTally>> regionDistribution({List<int>? foodIds}) =>
      _map.regionDistribution(foodIds: foodIds);

  Future<Region?> regionAt(double latitude, double longitude) =>
      _map.regionAt(latitude, longitude);

  Future<List<CountryOutline>> malaysiaOutlines() => _map.malaysiaOutlines();

  Future<List<CountryOutline>> malaysiaMaskOutlines() =>
      _map.malaysiaMaskOutlines();

  Future<List<FoodOccurrence>> foodOccurrences() => _map.foodOccurrences();

  /// Opening hours keyed by place (`"restaurant:12"`).
  ///
  /// Pass [placeKeys] when only some places are being drawn - the table holds a
  /// row per place per weekday, so reading all of it for a handful of pins is
  /// the most expensive read on the map.
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) => _map.openingHours(placeKeys: placeKeys);

  void clearMapCache() => _map.clearCache();

  Future<MapMarkerSet> mapMarkers({
    required double southLatitude,
    required double westLongitude,
    required double northLatitude,
    required double eastLongitude,
    required double zoom,
    required double maximumZoom,
    List<int>? foodIds,
    int limit = 400,
    MapSearchSelection search = MapSearchSelection.none,
  }) => _map.mapMarkers(
    southLatitude: southLatitude,
    westLongitude: westLongitude,
    northLatitude: northLatitude,
    eastLongitude: eastLongitude,
    zoom: zoom,
    maximumZoom: maximumZoom,
    foodIds: foodIds,
    limit: limit,
    search: search,
  );

  Future<({double? splitZoom, int memberCount})> clusterSplitZoom({
    required double latitude,
    required double longitude,
    required double zoom,
    required double maximumZoom,
    List<int>? foodIds,
    MapSearchSelection search = MapSearchSelection.none,
  }) => _map.clusterSplitZoom(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    maximumZoom: maximumZoom,
    foodIds: foodIds,
    search: search,
  );

  Future<List<MapPin>> clusterMembers({
    required double latitude,
    required double longitude,
    required double zoom,
    List<int>? foodIds,
    int limit = 200,
    MapSearchSelection search = MapSearchSelection.none,
  }) => _map.clusterMembers(
    latitude: latitude,
    longitude: longitude,
    zoom: zoom,
    foodIds: foodIds,
    limit: limit,
    search: search,
  );

  Future<List<MapPlace>> places() => _map.places();

  Future<List<MapPlaceHit>> searchPlaceNames(String needle, {int limit = 12}) =>
      _map.searchPlaceNames(needle, limit: limit);

  Future<MapDataStamp> mapDataStamp() => _map.mapDataStamp();

  bool get mockGpsSupported => _location.mockSupported;

  bool get mockGpsActive => _location.mockActive;

  Future<String?> setMockLocation(double latitude, double longitude) =>
      _location.setMockLocation(latitude, longitude);

  Future<void> stopMockLocation() => _location.stopMockLocation();

  Future<bool> ensureLocationPermission() =>
      _location.ensureLocationPermission();

  Future<TouristLocation> currentLocation() => _location.currentLocation();

  List<String> recentSearches() => _searchHistory.read();

  Future<void> saveRecentSearches(List<String> terms) =>
      _searchHistory.write(terms);

  Future<void> clearRecentSearches() => _searchHistory.clear();

  Future<SwipeSession?> getSwipeSession({
    required String touristId,
    required String stateCode,
  }) => _swipe.getSession(touristId: touristId, stateCode: stateCode);

  Future<void> saveSwipeSession(SwipeSession session) =>
      _swipe.saveSession(session);

  Future<void> deleteSwipeSession({
    required String touristId,
    required String stateCode,
  }) => _swipe.deleteSession(touristId: touristId, stateCode: stateCode);
}
