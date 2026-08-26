import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/restaurant.dart';
import 'camera_repository.dart';
import 'location_repository.dart';
import 'map_repository.dart';
import 'recognition_repository.dart';
import 'restaurant_repository.dart';

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
  DiscoveryRepositoryFacade({
    @visibleForTesting RestaurantRepository? restaurant,
    @visibleForTesting RecognitionRepository? recognition,
  }) : restaurant = restaurant ?? RestaurantRepository(),
       recognition = recognition ?? RecognitionRepository();

  final RestaurantRepository restaurant;
  final RecognitionRepository recognition;

  /// REQ102 - the Malaysian regions and the food occurrences plotted on them.
  final MapRepository map = MapRepository();

  /// REQ102_6 / REQ102_7 - GPS permission and fixes.
  final LocationRepository location = LocationRepository();

  /// REQ106_1 - the camera permission that gates photo capture on
  /// `FoodRecognitionView`.
  final CameraRepository camera = CameraRepository();

  Future<List<Restaurant>> getRestaurants() => restaurant.getRestaurants();
}
