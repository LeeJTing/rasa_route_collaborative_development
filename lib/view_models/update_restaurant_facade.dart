import '../domain_model/restaurant.dart';
import 'dashboard_view_model.dart';

/// VIEWMODEL FACADE (inbound) for restaurant and map-data refreshes.
///
/// `RestaurantMonitor` publishes here; the facade decides which ViewModels hear
/// about it. Two things travel this way, by the two routes described in
/// `current_location_facade.dart`:
///
/// ```text
/// RestaurantMonitor
///   -> publishNearby()          -> registered RestaurantUpdateListeners
///   -> publishMapDataChanged()  -> DashboardViewModel.onMapDataChanged()  [static]
/// ```
///
/// The second exists because of a problem the first cannot solve: one tourist
/// submits a landmark, and every *other* tourist's map is now out of date with
/// no way to know it. The monitor notices, and the dashboard offers an Update
/// button rather than silently re-fetching under the tourist's fingers.
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

  /// Called by `RestaurantMonitor` when the map data behind the dashboard has
  /// changed - somebody added a landmark, or new restaurants landed.
  ///
  /// Goes to a **static** entry point rather than a listener list, so the
  /// pending-update flag survives the ViewModel being disposed and rebuilt: a
  /// tourist who switches tabs and comes back still sees the prompt.
  ///
  /// [newLandmarks] is how many landmarks appeared since the last check, for
  /// the wording of the message. Zero means something else changed.
  void publishMapDataChanged({required int newLandmarks}) {
    try {
      DashboardViewModel.onMapDataChanged(newLandmarks: newLandmarks);
    } catch (_) {
      // One broken ViewModel must not stop the monitor.
    }
  }

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
