import '../../domain_model/restaurant.dart';
import '../../domain_model/origin_verification.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_distribution.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/region.dart';
import '../../domain_model/swipe_session.dart';
import 'auth_repository.dart';
import 'camera_repository.dart';
import 'dietary_restriction_repository.dart';
import 'food_knowledge_repository.dart';
import 'location_repository.dart';
import 'map_repository.dart';
import 'recognition_repository.dart';
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
  final RecognitionRepository recognition = RecognitionRepository();

  /// REQ102 - the Malaysian regions and the food occurrences plotted on them.
  final MapRepository map;

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

  Future<Restaurant?> getRestaurantById(int restaurantId) =>
      restaurant.getRestaurantById(restaurantId);

  Future<List<LocalFood>> getLocalFoods() => food.getFoods();

  Future<Set<int>> favouriteFoodIdsForTourist(String touristId) =>
      food.favouriteFoodIdsForTourist(touristId);

  Future<List<DietaryRestriction>> dietaryRestrictionsForTourist(
    String touristId,
  ) => dietaryRestriction.restrictionsForTourist(touristId);

  Future<Map<int, Set<int>>> dietaryRestrictionIdsByFood() =>
      dietaryRestriction.restrictionIdsByFood();

  Future<List<Region>> malaysiaRegions() => map.malaysiaRegions();

  Future<List<FoodOccurrence>> foodOccurrences() => map.foodOccurrences();

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
