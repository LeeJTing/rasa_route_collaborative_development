import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/matches_recommendation.dart';
import '../domain_model/restaurant.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import 'current_location_facade.dart';
import 'update_restaurant_facade.dart';

enum RestaurantSource { google, submitted }

/// Quick Mode state: nearby restaurants, source tab and expanded menus.
class RestaurantRecommendationViewModel extends BaseViewModel
    implements CurrentLocationListener, RestaurantUpdateListener {
  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

  @protected
  CurrentLocationFacade createLocationFacade() => CurrentLocationFacade();

  @protected
  UpdateRestaurantFacade createRestaurantFacade() => UpdateRestaurantFacade();

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();
  late final CurrentLocationFacade locationFacade = createLocationFacade();
  late final UpdateRestaurantFacade restaurantFacade = createRestaurantFacade();

  TouristLocation _location = TouristLocation.unknown;
  List<Restaurant> _restaurants = const <Restaurant>[];
  List<SubmittedLandmarkRecommendation> _landmarks =
      const <SubmittedLandmarkRecommendation>[];
  RestaurantSource _source = RestaurantSource.google;
  final Set<int> _expandedRestaurantIds = <int>{};
  final Set<int> _expandedLandmarkIds = <int>{};
  bool _isLoadingNearby = false;
  bool _reloadNearbyRequested = false;

  List<Restaurant> get restaurants => _restaurants;
  List<SubmittedLandmarkRecommendation> get landmarks => _landmarks;
  RestaurantSource get source => _source;
  bool get selectedSourceIsEmpty => switch (_source) {
    RestaurantSource.google => _restaurants.isEmpty,
    RestaurantSource.submitted => _landmarks.isEmpty,
  };
  bool isRestaurantExpanded(int id) => _expandedRestaurantIds.contains(id);
  bool isLandmarkExpanded(int id) => _expandedLandmarkIds.contains(id);

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

  Future<void> loadNearbyRestaurants() async {
    if (_isLoadingNearby) {
      _reloadNearbyRequested = true;
      return;
    }
    _isLoadingNearby = true;
    try {
      do {
        _reloadNearbyRequested = false;
        final TouristLocation requestedLocation = _location;
        await runGuarded(() async {
          final List<Object> results = await Future.wait(<Future<Object>>[
            discoveryLogic.getQuickModeRestaurants(location: requestedLocation),
            discoveryLogic.getQuickModeLandmarks(location: requestedLocation),
          ]);
          if (_reloadNearbyRequested || requestedLocation != _location) return;
          _restaurants = results[0] as List<Restaurant>;
          _landmarks = results[1] as List<SubmittedLandmarkRecommendation>;
          _sort();
        });
      } while (_reloadNearbyRequested);
    } finally {
      _isLoadingNearby = false;
    }
  }

  void selectSource(RestaurantSource source) {
    _source = source;
    safeNotifyListeners();
  }

  void toggleRestaurantExpanded(int id) {
    _expandedRestaurantIds.contains(id)
        ? _expandedRestaurantIds.remove(id)
        : _expandedRestaurantIds.add(id);
    safeNotifyListeners();
  }

  void toggleLandmarkExpanded(int id) {
    _expandedLandmarkIds.contains(id)
        ? _expandedLandmarkIds.remove(id)
        : _expandedLandmarkIds.add(id);
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
    _landmarks = List<SubmittedLandmarkRecommendation>.of(_landmarks)
      ..sort(
        (
          SubmittedLandmarkRecommendation a,
          SubmittedLandmarkRecommendation b,
        ) => a.distanceMetres.compareTo(b.distanceMetres),
      );
  }

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _location = location;
    loadNearbyRestaurants();
  }

  @override
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants) {
    // A monitor notification means the source data changed. Re-run Quick
    // Mode's radius, hours and dietary rules instead of accepting an
    // unfiltered background list.
    loadNearbyRestaurants();
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    restaurantFacade.unregister(this);
    super.dispose();
  }
}
