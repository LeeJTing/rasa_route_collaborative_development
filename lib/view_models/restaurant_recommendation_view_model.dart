import '../core/base_view_model.dart';
import '../domain_model/restaurant.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import 'current_location_facade.dart';
import 'update_restaurant_facade.dart';

enum RestaurantSource { google, submitted }

/// Quick Mode state: nearby restaurants, source tab and expanded menus.
class RestaurantRecommendationViewModel extends BaseViewModel
    implements CurrentLocationListener, RestaurantUpdateListener {
  final DiscoveryLogicFacade discoveryLogic = DiscoveryLogicFacade();
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();
  final UpdateRestaurantFacade restaurantFacade = UpdateRestaurantFacade();

  static const int _restaurantLimit = 20;

  TouristLocation _location = TouristLocation.unknown;
  List<Restaurant> _restaurants = const <Restaurant>[];
  RestaurantSource _source = RestaurantSource.google;
  final Set<int> _expandedIds = <int>{};

  List<Restaurant> get restaurants =>
      _source == RestaurantSource.google ? _restaurants : const <Restaurant>[];
  RestaurantSource get source => _source;
  bool isExpanded(int id) => _expandedIds.contains(id);

  @override
  Future<void> onInit() async {
    _location = locationFacade.latest;
    // A9 obtains the fix before navigating here. Register without replaying
    // that same fix, otherwise onCurrentLocationChanged and this initial load
    // race each other and issue duplicate Supabase requests.
    locationFacade.register(this, replayLatest: false);
    restaurantFacade.register(this);
    await loadNearbyRestaurants();
  }

  Future<void> loadNearbyRestaurants() => runGuarded(() async {
    _restaurants = await discoveryLogic.getQuickModeRestaurants(
      location: _location,
      limit: _restaurantLimit,
    );
    _sort();
  });

  void selectSource(RestaurantSource source) {
    _source = source;
    safeNotifyListeners();
  }

  void toggleExpanded(int id) {
    _expandedIds.contains(id) ? _expandedIds.remove(id) : _expandedIds.add(id);
    safeNotifyListeners();
  }

  String distanceLabel(Restaurant restaurant) {
    final double? metres = restaurant.distanceMetres;
    if (metres == null) return 'Distance unavailable';
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  void _sort() {
    _restaurants = List<Restaurant>.of(_restaurants)
      ..sort((Restaurant a, Restaurant b) {
        final int result = (a.distanceMetres ?? double.infinity).compareTo(
          b.distanceMetres ?? double.infinity,
        );
        return result;
      });
  }

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _location = location;
    loadNearbyRestaurants();
  }

  @override
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants) {
    _restaurants = restaurants;
    _sort();
    safeNotifyListeners();
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    restaurantFacade.unregister(this);
    super.dispose();
  }
}
