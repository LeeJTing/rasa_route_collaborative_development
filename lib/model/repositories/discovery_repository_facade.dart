import 'recognition_repository.dart';
import 'restaurant_repository.dart';

/// Everything about finding food out in the world: restaurants, menus and photo recognition.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class DiscoveryRepositoryFacade {
  DiscoveryRepositoryFacade();

  final RestaurantRepository restaurant = RestaurantRepository();
  final RecognitionRepository recognition = RecognitionRepository();
}
