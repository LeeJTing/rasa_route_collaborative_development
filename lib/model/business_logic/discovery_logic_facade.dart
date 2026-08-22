import 'food_discovery_logic.dart';
import 'food_recognition_logic.dart';
import 'restaurant_discovery_logic.dart';
import '../../domain_model/restaurant.dart';
import '../data_models/location_data_model.dart';

/// Finding food in the real world: restaurants, menus and photo recognition.
/// Used by the RestaurantRecommendation, RestaurantDetail, RestaurantItemList
/// and FoodRecognition ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class DiscoveryLogicFacade {
  DiscoveryLogicFacade();

  final RestaurantDiscoveryLogic restaurantDiscovery =
      RestaurantDiscoveryLogic();
  final FoodDiscoveryLogic foodDiscovery = FoodDiscoveryLogic();
  final FoodRecognitionLogic foodRecognition = FoodRecognitionLogic();

  Future<List<Restaurant>> getQuickModeRestaurants({
    required LocationDataModel location,
    required int limit,
  }) => restaurantDiscovery.nearbyWithAutomaticExpansion(
    location: location,
    limit: limit,
  );
}
