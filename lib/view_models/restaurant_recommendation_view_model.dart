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
  RestaurantRecommendationViewModel();

  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

  @protected
  DateTime currentTime() => DateTime.now();

  @protected
  CurrentLocationFacade createLocationFacade() => CurrentLocationFacade();

  @protected
  UpdateRestaurantFacade createRestaurantFacade() => UpdateRestaurantFacade();

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();
  late final CurrentLocationFacade locationFacade = createLocationFacade();
  late final UpdateRestaurantFacade restaurantFacade = createRestaurantFacade();

  /// Minimum gap between BACKGROUND reloads (a GPS fix or a monitor
  /// notification). The location stream can emit a fix for every few metres of
  /// movement - reloading on each one fired a fresh Supabase query burst
  /// (restaurants + items + dietary rules) while walking or driving with Quick
  /// Mode open. 30 s is far shorter than how long a "nearby" answer stays
  /// useful, so results never look stale while the request volume drops to a
  /// fraction.
  static const Duration _backgroundReloadCooldown = Duration(seconds: 30);

  TouristLocation _location = TouristLocation.unknown;
  List<Restaurant> _restaurants = const <Restaurant>[];
  List<SubmittedLandmarkRecommendation> _landmarks =
      const <SubmittedLandmarkRecommendation>[];
  RestaurantSource _source = RestaurantSource.google;
  final Set<int> _expandedRestaurantIds = <int>{};
  final Set<int> _expandedLandmarkIds = <int>{};
  bool _isLoadingNearby = false;
  bool _reloadNearbyRequested = false;

  DateTime? _lastBackgroundReloadAt;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

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

  /// Reload because a background event said the answer may have changed - a
  /// GPS fix, or the restaurant monitor noticing new data. These can arrive
  /// several times a minute (a fix per few metres of movement), so they are
  /// throttled: at most one background reload per [_backgroundReloadCooldown],
  /// and never one that stacks behind a reload already in flight. A change
  /// that arrives mid-flight is remembered and applied once the current load
  /// finishes, so the newest position is never dropped - only bursty requests
  /// are.
  void _reloadFromBackground() {
    // Never discard a location or monitor change that arrives while the
    // current request is still resolving. Queue one trailing refresh first;
    // the cooldown only suppresses separate completed request bursts.
    if (_reloadInFlight) {
      _reloadQueued = true;
      return;
    }
    final DateTime now = currentTime();
    final DateTime? last = _lastBackgroundReloadAt;
    if (last != null && now.difference(last) < _backgroundReloadCooldown) {
      // Too soon after the last background reload - the fix is remembered
      // (we already stored _location) and the NEXT allowed reload will use it.
      return;
    }
    _lastBackgroundReloadAt = now;
    _performReload();
  }

  Future<void> _performReload() async {
    _reloadInFlight = true;
    try {
      await loadNearbyRestaurants();
    } finally {
      _reloadInFlight = false;
      if (_reloadQueued) {
        _reloadQueued = false;
        _lastBackgroundReloadAt = currentTime();
        _performReload();
      }
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
    _reloadFromBackground();
  }

  @override
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants) {
    // A monitor notification means the source data changed. Re-run Quick
    // Mode's radius, hours and dietary rules instead of accepting an
    // unfiltered background list.
    _reloadFromBackground();
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    restaurantFacade.unregister(this);
    super.dispose();
  }
}
