import '../core/base_view_model.dart';
import '../domain_model/restaurant.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import '../model/data_models/location_data_model.dart';
import 'current_location_facade.dart';
import 'update_restaurant_facade.dart';

/// ViewModel for `RestaurantRecommendationView`.
///
/// Nearby restaurants, refreshed in the background by RestaurantMonitor.
///
/// Implements [CurrentLocationListener] and [RestaurantUpdateListener] so a background process can
/// push updates in through an inbound ViewModel facade. Register in `onInit`,
/// unregister in `dispose` - forgetting the second leaks this object.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class RestaurantRecommendationViewModel extends BaseViewModel implements CurrentLocationListener, RestaurantUpdateListener {
  RestaurantRecommendationViewModel();

  final DiscoveryLogicFacade discoveryLogic = DiscoveryLogicFacade();

  /// Inbound: `LocationMonitor` publishes here.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  /// Inbound: `RestaurantMonitor` publishes here.
  final UpdateRestaurantFacade restaurantFacade = UpdateRestaurantFacade();

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
    restaurantFacade.register(this);
  }

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(LocationDataModel location) {
    _location = location;
    safeNotifyListeners();
  }

  LocationDataModel _location = LocationDataModel.unknown;

  LocationDataModel get location => _location;

  /// Pushed by `RestaurantMonitor` through [UpdateRestaurantFacade]. The list
  /// arrives without this screen asking for it - that is the point of an
  /// inbound ViewModel facade.
  @override
  void onNearbyRestaurantsUpdated(List<Restaurant> restaurants) {
    _restaurants = restaurants;
    setReady();
  }

  List<Restaurant> _restaurants = const <Restaurant>[];

  List<Restaurant> get restaurants => _restaurants;

  @override
  void dispose() {
    locationFacade.unregister(this);
    restaurantFacade.unregister(this);
    super.dispose();
  }
}
