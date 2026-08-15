import '../facades/discovery_logic_facade.dart';
import '../../repositories/facades/restaurant_repository.dart';
import '../../repositories/facades/food_repository_facade.dart';
import '../../repositories/facades/location_repository.dart';

class RestaurantDiscoveryLogic implements DiscoveryLogicFacade {
  final RestaurantRepository restaurantRepository;
  final FoodRepository foodRepository;
  final LocationRepository locationRepository;

  RestaurantDiscoveryLogic({
    required this.restaurantRepository,
    required this.foodRepository,
    required this.locationRepository,
  });

  // TODO: Implement RestaurantDiscoveryLogic by coordinating repository facades only.
}
