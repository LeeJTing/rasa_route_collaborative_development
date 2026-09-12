import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/restaurant.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import 'current_location_facade.dart';

/// ViewModel for `RestaurantDetailView`.
///
/// One restaurant with its opening hours and menu preview. Reporting lives on
/// the separate full-screen report page (`ReportPlaceView` /
/// `ReportPlaceViewModel`), not here - this screen just opens it.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class RestaurantDetailViewModel extends BaseViewModel {
  RestaurantDetailViewModel();

  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  Restaurant? _restaurant;
  int? _restaurantId;

  Restaurant? get restaurant => _restaurant;

  void selectRestaurant(int? restaurantId) {
    _restaurantId = restaurantId;
  }

  @override
  Future<void> onInit() {
    final int? restaurantId = _restaurantId;
    return restaurantId == null
        ? rejectMissingRestaurantId()
        : loadRestaurant(restaurantId);
  }

  Future<void> loadRestaurant(int restaurantId) => runGuarded(() async {
    _restaurantId = restaurantId;
    _restaurant = await discoveryLogic.getRestaurantById(
      restaurantId,
      origin: locationFacade.latest,
    );
    if (_restaurant == null) {
      throw Exception('Restaurant details are unavailable.');
    }
  });

  Future<void> retry() async {
    final int? restaurantId = _restaurantId;
    if (restaurantId != null) await loadRestaurant(restaurantId);
  }

  Future<void> rejectMissingRestaurantId() => runGuarded(() async {
    throw Exception('No restaurant was selected. Please return to the map.');
  });
}
