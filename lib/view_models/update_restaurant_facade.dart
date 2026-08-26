import '../domain_model/restaurant.dart';

/// VIEWMODEL FACADE (inbound) for restaurant refreshes.
///
/// `RestaurantMonitor` re-fetches nearby restaurants on a timer and publishes
/// here; any ViewModel that implements [RestaurantUpdateListener] and registers
/// gets told. See `current_location_facade.dart` for the rules.
///
/// A singleton - `UpdateRestaurantFacade()` always returns the same instance.
class UpdateRestaurantFacade {
  factory UpdateRestaurantFacade() => _instance;

  UpdateRestaurantFacade._();

  static final UpdateRestaurantFacade _instance = UpdateRestaurantFacade._();

  final List<RestaurantUpdateListener> _listeners =
      <RestaurantUpdateListener>[];

  List<Restaurant> _latestNearby = const <Restaurant>[];

  List<Restaurant> get latestNearby => _latestNearby;

  void register(RestaurantUpdateListener listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
    if (_latestNearby.isNotEmpty) {
      listener.onNearbyRestaurantsUpdated(_latestNearby);
    }
  }

  void unregister(RestaurantUpdateListener listener) =>
      _listeners.remove(listener);

  /// Called by `RestaurantMonitor`. Fans out to every registered ViewModel.
  void publishNearby(List<Restaurant> restaurants) {
    _latestNearby = restaurants;
    for (final RestaurantUpdateListener listener
        in List<RestaurantUpdateListener>.of(_listeners)) {
      try {
        listener.onNearbyRestaurantsUpdated(restaurants);
      } catch (_) {
        // Ignore - one bad listener must not stop the rest.
      }
    }
  }
}

/// Implemented by any ViewModel that shows nearby restaurants.
abstract interface class RestaurantUpdateListener {
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants);
}
