import 'package:meta/meta.dart' show visibleForTesting;

import '../core/base_view_model.dart';
import '../domain_model/restaurant.dart';
import '../model/business_logic/discovery_logic_facade.dart';

enum RestaurantReportReason {
  noLongerExists,
  incorrectOperatingHours,
  incorrectLocation,
  listedLocalFoodUnavailable,
  incorrectInformation,
}

/// ViewModel for `RestaurantDetailView`.
///
/// One restaurant with its opening hours and menu preview.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class RestaurantDetailViewModel extends BaseViewModel {
  RestaurantDetailViewModel({
    @visibleForTesting DiscoveryLogicFacade? discoveryLogic,
  }) : discoveryLogic = discoveryLogic ?? DiscoveryLogicFacade();

  final DiscoveryLogicFacade discoveryLogic;

  Restaurant? _restaurant;
  int? _restaurantId;
  bool _reportSubmitted = false;

  Restaurant? get restaurant => _restaurant;
  bool get reportSubmitted => _reportSubmitted;

  Future<void> loadRestaurant(int restaurantId) => runGuarded(() async {
    _restaurantId = restaurantId;
    _restaurant = await discoveryLogic.getRestaurantById(restaurantId);
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

  Future<void> submitReport(RestaurantReportReason reason) async {
    if (_restaurant == null) return;

    // UI-only iteration. A later repository iteration will submit the reason
    // through an authenticated RPC and enforce the unique-user threshold.
    _reportSubmitted = true;
    safeNotifyListeners();
  }

  void consumeReportSubmitted() {
    if (!_reportSubmitted) return;
    _reportSubmitted = false;
    safeNotifyListeners();
  }
}
