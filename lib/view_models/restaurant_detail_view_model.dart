import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/restaurant.dart';
import '../domain_model/restaurant_report_reason.dart';
import '../model/business_logic/discovery_logic_facade.dart';
import 'update_restaurant_facade.dart';

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
  RestaurantDetailViewModel();

  @protected
  DiscoveryLogicFacade createDiscoveryLogic() => DiscoveryLogicFacade();

  late final DiscoveryLogicFacade discoveryLogic = createDiscoveryLogic();

  /// Broadcasts "this tourist changed the map themselves" (a report just
  /// froze the restaurant they were viewing) so every live dashboard silently
  /// drops its caches and re-reads - the frozen pin disappears without a
  /// banner.
  final UpdateRestaurantFacade mapRefresh = UpdateRestaurantFacade();

  Restaurant? _restaurant;
  int? _restaurantId;
  bool _reportSubmitted = false;
  bool _alreadyReported = false;
  bool _reportFailed = false;
  bool _requiresSignIn = false;
  bool _reportFrozePlace = false;

  Restaurant? get restaurant => _restaurant;
  bool get reportSubmitted => _reportSubmitted;

  /// True when [submitReport] found this tourist already reported this
  /// restaurant - the View thanks them without counting the report twice.
  bool get alreadyReported => _alreadyReported;

  /// True when [submitReport] could not reach the backend - the View shows a
  /// retry message instead of pretending the report went through.
  bool get reportFailed => _reportFailed;

  /// True when [submitReport] was attempted while signed out - reporting is a
  /// signed-in feature, so nothing was written and the View asks the tourist
  /// to sign in.
  bool get requiresSignIn => _requiresSignIn;

  /// True when THIS report crossed the freeze threshold and froze the
  /// restaurant - the View leaves the page (back to the map) so the now-hidden
  /// pin is no longer shown.
  bool get reportFrozePlace => _reportFrozePlace;

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

  /// Records a report against this restaurant in the shared `report` table
  /// (signed-in only; per-tourist dedupe, count bump, freeze once it passes
  /// the threshold - see `RestaurantDiscoveryLogic.submitRestaurantReport`).
  /// Failures are surfaced through [reportFailed] rather than throwing into
  /// the sheet.
  Future<void> submitReport(RestaurantReportReason reason) async {
    final Restaurant? restaurant = _restaurant;
    if (restaurant == null) return;
    try {
      final ({bool requiresSignIn, bool alreadyReported, bool frozePlace})
      outcome = await discoveryLogic.submitRestaurantReport(
        restaurantId: restaurant.id,
        reason: reason,
      );
      if (outcome.requiresSignIn) {
        _requiresSignIn = true;
      } else {
        _alreadyReported = outcome.alreadyReported;
        _reportSubmitted = !outcome.alreadyReported;
        _reportFrozePlace = outcome.frozePlace;
        if (outcome.frozePlace) {
          mapRefresh.publishOwnMapDataChanged();
        }
      }
    } catch (_) {
      _reportFailed = true;
    } finally {
      safeNotifyListeners();
    }
  }

  void consumeReportSubmitted() {
    if (!_reportSubmitted &&
        !_alreadyReported &&
        !_reportFailed &&
        !_requiresSignIn &&
        !_reportFrozePlace) {
      return;
    }
    _reportSubmitted = false;
    _alreadyReported = false;
    _reportFailed = false;
    _requiresSignIn = false;
    _reportFrozePlace = false;
    safeNotifyListeners();
  }
}
