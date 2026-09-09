import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/origin_verification.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/region.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/swipe_session.dart';
import 'auth_repository.dart';
import 'camera_repository.dart';
import 'dietary_restriction_repository.dart';
import 'food_knowledge_repository.dart';
import 'location_repository.dart';
import 'map_repository.dart';
import 'recognition_repository.dart';
import 'report_repository.dart';
import 'restaurant_repository.dart';
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

  final RestaurantRepository restaurant = RestaurantRepository();
  final DietaryRestrictionRepository dietaryRestriction =
      DietaryRestrictionRepository();
  final RecognitionRepository recognition = RecognitionRepository();
  final AuthRepository auth = AuthRepository();
  final FoodKnowledgeRepository food = FoodKnowledgeRepository();
  final SwipeRepository swipe = SwipeRepository();

  /// Shared tourist report table (kind + place_id + reason).
  final ReportRepository report = ReportRepository();

  /// REQ102 - the Malaysian regions and the food occurrences plotted on them.
  final MapRepository map = MapRepository();

  /// REQ102_6 / REQ102_7 - GPS permission and fixes.
  final LocationRepository location = LocationRepository();

  /// REQ106_1 - the camera permission that gates photo capture on
  /// `FoodRecognitionView`.
  final CameraRepository camera = CameraRepository();

  /// 3-step origin verification for a dish name (Option C gate) - three
  /// separately-framed Gemini questions, fail-closed.
  Future<OriginVerification> verifyDishOrigin(String dishName) =>
      recognition.verifyDishOrigin(dishName);

  Future<List<Restaurant>> getRestaurants() => restaurant.getRestaurants();

  Future<List<Restaurant>> getRestaurantsByIds(List<int> restaurantIds) =>
      restaurant.getRestaurantsByIds(restaurantIds);

  Future<List<RestaurantItem>> getRestaurantItemsByRestaurantIds(
    List<int> restaurantIds,
  ) => restaurant.getRestaurantItemsByRestaurantIds(restaurantIds);

  Future<List<DietaryRestriction>> getCurrentDietaryRestrictions() =>
      dietaryRestriction.restrictionsForCurrentTourist();

  Future<Map<int, List<int>>> getRestrictionIdsByFood() =>
      dietaryRestriction.restrictionIdsByFood();

  Future<Restaurant?> getRestaurantById(int restaurantId) =>
      restaurant.getRestaurantById(restaurantId);

  Future<List<LocalFood>> getLocalFoods() => food.getFoods();

  Future<List<LocalFood>> searchLocalFoods(String query) =>
      food.searchFoods(query);

  Future<Set<int>> favouriteFoodIdsForTourist(String touristId) =>
      food.favouriteFoodIdsForTourist(touristId);

  Future<List<DietaryRestriction>> dietaryRestrictionsForTourist(
    String touristId,
  ) => dietaryRestriction.restrictionsForTourist(touristId);

  Future<Map<int, Set<int>>> dietaryRestrictionIdsByFood() async {
    final Map<int, List<int>> ids = await dietaryRestriction
        .restrictionIdsByFood();
    return ids.map(
      (int foodId, List<int> restrictionIds) =>
          MapEntry<int, Set<int>>(foodId, restrictionIds.toSet()),
    );
  }

  Future<List<Region>> malaysiaRegions() => map.malaysiaRegions();

  Future<List<FoodOccurrence>> foodOccurrences() => map.foodOccurrences();

  /// Opening hours keyed by place (`"restaurant:12"`).
  ///
  /// Pass [placeKeys] when only some places are being drawn - the table holds a
  /// row per place per weekday, so reading all of it for a handful of pins is
  /// the most expensive read on the map.
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) => map.openingHours(placeKeys: placeKeys);

  /// Flat reporting API for restaurant discovery logic. Business logic must
  /// not reach through this facade to concrete repositories.
  Future<bool> restaurantReportAlreadyExists({
    required int restaurantId,
    required String touristId,
  }) => report.alreadyReported(
    kind: 'restaurant',
    placeId: restaurantId,
    touristId: touristId,
  );

  Future<void> insertRestaurantReport({
    required int restaurantId,
    required String reason,
    required String touristId,
  }) => report.insertReport(
    kind: 'restaurant',
    placeId: restaurantId,
    reason: reason,
    touristId: touristId,
  );

  Future<int> incrementRestaurantReportCount(int restaurantId) =>
      restaurant.incrementReportCount(restaurantId);

  Future<void> freezeRestaurant(int restaurantId) =>
      restaurant.freeze(restaurantId);

  void clearMapCache() => map.clearCache();

  Future<String?> currentTouristId() => auth.currentTouristId();

  Future<SwipeSession?> getSwipeSession({
    required String touristId,
    required String stateCode,
  }) => swipe.getSession(touristId: touristId, stateCode: stateCode);

  Future<void> saveSwipeSession(SwipeSession session) =>
      swipe.saveSession(session);

  Future<void> deleteSwipeSession({
    required String touristId,
    required String stateCode,
  }) => swipe.deleteSession(touristId: touristId, stateCode: stateCode);
}
