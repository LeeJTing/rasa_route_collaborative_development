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

  static const List<String> foodTypeOptions = <String>[
    'Food',
    'Beverage',
    'Fruit',
    'Dessert',
    'Kuih',
  ];

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
  /// notification).
  static const Duration _backgroundReloadCooldown = Duration(seconds: 30);

  TouristLocation _location = TouristLocation.unknown;
  List<Restaurant> _restaurants = const <Restaurant>[];
  List<SubmittedLandmarkRecommendation> _landmarks =
  const <SubmittedLandmarkRecommendation>[];
  RestaurantSource _source = RestaurantSource.google;

  // No "All" option - Quick Mode always searches for one specific food type,
  // and 'Food' is the default the screen opens with.
  String _selectedFoodType = foodTypeOptions.first;
  final Set<int> _expandedRestaurantIds = <int>{};
  final Set<int> _expandedLandmarkIds = <int>{};

  /// Results already fetched for a location + food type.
  ///
  /// This makes Food -> Fruit -> Food instant on the second Food selection,
  /// while still keeping separate answers for different GPS positions.
  final Map<String, _QuickModeCacheEntry> _nearbyCache =
  <String, _QuickModeCacheEntry>{};

  /// Incremented whenever cached data is invalidated. A request that started
  /// before invalidation is then prevented from putting stale results back.
  int _cacheVersion = 0;

  bool _isLoadingNearby = false;
  bool _reloadNearbyRequested = false;
  bool _forceReloadRequested = false;

  bool _isLoadingResult = false;
  bool get isLoadingResult => _isLoadingResult;

  DateTime? _lastBackgroundReloadAt;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

  List<Restaurant> get restaurants => _restaurants;
  String get selectedFoodType => _selectedFoodType;

  // The nearby search is already re-run per selected food type (see
  // [loadNearbyRestaurants]), so `_restaurants` only ever holds restaurants
  // matching the current selection - nothing left to filter client-side.
  List<Restaurant> get visibleRestaurants => _restaurants;

  List<SubmittedLandmarkRecommendation> get landmarks => _landmarks;
  RestaurantSource get source => _source;

  bool get selectedSourceIsEmpty => switch (_source) {
    RestaurantSource.google => visibleRestaurants.isEmpty,
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

  /// Loads the current location + food-type result.
  ///
  /// Cache is checked BEFORE [_isLoadingNearby]. This matters when another
  /// filter is still loading:
  ///
  /// Food cached -> Fruit loading -> user selects Food again
  ///
  /// Food is restored immediately from cache instead of waiting for Fruit.
  /// The Fruit request may still finish in the background and be cached, but
  /// it cannot replace the currently selected Food result.
  Future<void> loadNearbyRestaurants({bool forceRefresh = false}) async {
    final TouristLocation currentLocation = _location;
    final String currentFoodType = _selectedFoodType;
    final String currentKey = _cacheKey(
      currentLocation,
      currentFoodType,
    );

    // IMPORTANT: read cache before checking whether another request is active.
    if (!forceRefresh) {
      final _QuickModeCacheEntry? cached = _nearbyCache[currentKey];

      if (cached != null) {
        _applyCached(cached);

        // The currently running request may belong to another food type.
        // Since the selected type already has usable cached data, the UI
        // should stop showing its loading indicator immediately.
        _isLoadingResult = false;

        safeNotifyListeners();
        return;
      }
    }

    // The selected type has no cache. If another request is already running,
    // remember that this selection needs to be processed afterwards.
    if (_isLoadingNearby) {
      _reloadNearbyRequested = true;

      if (forceRefresh) {
        _forceReloadRequested = true;
      }

      _isLoadingResult = true;
      safeNotifyListeners();
      return;
    }

    _isLoadingNearby = true;
    _isLoadingResult = true;
    safeNotifyListeners();

    try {
      bool forceNextRequest = forceRefresh;

      do {
        _reloadNearbyRequested = false;

        if (_forceReloadRequested) {
          forceNextRequest = true;
          _forceReloadRequested = false;
        }

        final TouristLocation requestedLocation = _location;
        final String requestedFoodType = _selectedFoodType;
        final String key = _cacheKey(
          requestedLocation,
          requestedFoodType,
        );

        // Another request may have populated this cache entry while the loop
        // was waiting. Use it rather than querying again.
        if (!forceNextRequest) {
          final _QuickModeCacheEntry? cached = _nearbyCache[key];

          if (cached != null) {
            if (!_reloadNearbyRequested &&
                requestedLocation == _location &&
                requestedFoodType == _selectedFoodType) {
              _applyCached(cached);
              _isLoadingResult = false;
              safeNotifyListeners();
            }

            continue;
          }
        }

        forceNextRequest = false;
        final int requestCacheVersion = _cacheVersion;

        await runGuarded(() async {
          final List<Object> results = await Future.wait(<Future<Object>>[
            discoveryLogic.getQuickModeRestaurants(
              location: requestedLocation,
              foodType: requestedFoodType,
            ),
            discoveryLogic.getQuickModeLandmarks(
              location: requestedLocation,
              foodType: requestedFoodType,
            ),
          ]);

          List<Restaurant> restaurants =
          results[0] as List<Restaurant>;

          List<SubmittedLandmarkRecommendation> landmarks =
          results[1] as List<SubmittedLandmarkRecommendation>;

          restaurants = _sortedRestaurants(restaurants);
          landmarks = _sortedLandmarks(landmarks);

          final _QuickModeCacheEntry entry = _QuickModeCacheEntry(
            restaurants: restaurants,
            landmarks: landmarks,
          );

          // Do not repopulate cache with stale data from a request that began
          // before a profile/source-data invalidation.
          if (requestCacheVersion == _cacheVersion) {
            _nearbyCache[key] = entry;
          }

          // This request may no longer match the currently selected filter.
          // Keep the result in cache, but never let it overwrite the UI.
          if (_reloadNearbyRequested ||
              requestedLocation != _location ||
              requestedFoodType != _selectedFoodType) {
            return;
          }

          _applyCached(entry);
        });
      } while (_reloadNearbyRequested);
    } finally {
      _isLoadingNearby = false;
      _isLoadingResult = false;
      safeNotifyListeners();
    }
  }

  /// Clears all Quick Mode result caches.
  ///
  /// Call this when profile/dietary settings or underlying place data changes,
  /// because those changes can alter every food-type result.
  void clearNearbyCache() {
    _nearbyCache.clear();
    _cacheVersion++;
  }

  /// Profile preferences may affect dietary filtering, so cached answers are
  /// no longer valid after returning from Profile.
  Future<void> refreshAfterProfileChange() async {
    clearNearbyCache();
    await loadNearbyRestaurants(forceRefresh: true);
  }

  /// Reload because a background event said the answer may have changed - a
  /// GPS fix, or the restaurant monitor noticing new data.
  void _reloadFromBackground({bool sourceDataChanged = false}) {
    if (sourceDataChanged) {
      clearNearbyCache();
    }

    // Never discard a location or monitor change that arrives while the
    // current request is still resolving.
    if (_reloadInFlight) {
      _reloadQueued = true;
      if (sourceDataChanged) _forceReloadRequested = true;
      return;
    }

    final DateTime now = currentTime();
    final DateTime? last = _lastBackgroundReloadAt;

    if (last != null && now.difference(last) < _backgroundReloadCooldown) {
      return;
    }

    _lastBackgroundReloadAt = now;
    _performReload(forceRefresh: sourceDataChanged);
  }

  Future<void> _performReload({bool forceRefresh = false}) async {
    _reloadInFlight = true;

    try {
      await loadNearbyRestaurants(forceRefresh: forceRefresh);
    } finally {
      _reloadInFlight = false;

      if (_reloadQueued) {
        _reloadQueued = false;

        final bool forceQueuedReload = _forceReloadRequested;
        _forceReloadRequested = false;

        _lastBackgroundReloadAt = currentTime();
        _performReload(forceRefresh: forceQueuedReload);
      }
    }
  }

  void selectSource(RestaurantSource source) {
    if (_source == source) return;

    _source = source;

    _expandedRestaurantIds.clear();
    _expandedLandmarkIds.clear();

    safeNotifyListeners();
  }

  // No "All" - each type has its own server-side result. Previously every
  // selection always re-queried; now an already-loaded location/type pair is
  // restored from [_nearbyCache].
  Future<void> selectFoodType(String foodType) async {
    final String normalized = foodType.trim();

    if (!foodTypeOptions.contains(normalized)) return;
    if (_selectedFoodType == normalized) return;

    _selectedFoodType = normalized;

    // Close all expanded cards when changing food-type filter.
    _expandedRestaurantIds.clear();
    _expandedLandmarkIds.clear();

    safeNotifyListeners();

    await loadNearbyRestaurants();
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

  String _cacheKey(TouristLocation location, String foodType) {
    if (!location.isKnown) return 'unknown|$foodType';

    // Four decimal places is roughly 11 m in latitude, which is precise enough
    // for Quick Mode while avoiding cache misses from tiny GPS jitter.
    return '${location.latitude.toStringAsFixed(4)}|'
        '${location.longitude.toStringAsFixed(4)}|'
        '$foodType';
  }

  void _applyCached(_QuickModeCacheEntry entry) {
    _restaurants = entry.restaurants;
    _landmarks = entry.landmarks;
  }

  List<Restaurant> _sortedRestaurants(List<Restaurant> restaurants) {
    final List<Restaurant> sorted = List<Restaurant>.of(restaurants)
      ..sort((Restaurant a, Restaurant b) {
        return (a.distanceMetres ?? double.infinity).compareTo(
          b.distanceMetres ?? double.infinity,
        );
      });

    return List<Restaurant>.unmodifiable(sorted);
  }

  List<SubmittedLandmarkRecommendation> _sortedLandmarks(
      List<SubmittedLandmarkRecommendation> landmarks,
      ) {
    final List<SubmittedLandmarkRecommendation> sorted =
    List<SubmittedLandmarkRecommendation>.of(landmarks)
      ..sort(
            (
            SubmittedLandmarkRecommendation a,
            SubmittedLandmarkRecommendation b,
            ) => a.distanceMetres.compareTo(b.distanceMetres),
      );

    return List<SubmittedLandmarkRecommendation>.unmodifiable(sorted);
  }

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _location = location;

    // Location is part of the cache key, so revisiting the same rounded
    // position may reuse a valid result while a genuinely new position loads
    // its own result.
    _reloadFromBackground();
  }

  @override
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants) {
    // Source data changed, so every cached food-type answer may now be stale.
    _reloadFromBackground(sourceDataChanged: true);
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    restaurantFacade.unregister(this);
    super.dispose();
  }
}

class _QuickModeCacheEntry {
  const _QuickModeCacheEntry({
    required this.restaurants,
    required this.landmarks,
  });

  final List<Restaurant> restaurants;
  final List<SubmittedLandmarkRecommendation> landmarks;
}
