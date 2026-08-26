import 'dart:async';

import '../../domain_model/map_data_stamp.dart';
import '../../view_models/current_location_facade.dart';
import '../../view_models/update_restaurant_facade.dart';
import '../repositories/discovery_repository_facade.dart';

/// Keeps the nearby-restaurant list fresh in the background.
///
/// Reads down through a **repository facade** and writes up through a
/// **ViewModel facade**. It also listens on [CurrentLocationFacade], so it is
/// both a consumer and a producer of inbound facades. See `LocationMonitor` for
/// the rules background processes follow.
class RestaurantMonitor {
  RestaurantMonitor();

  /// Down: where the restaurants come from.
  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();

  /// Up: how the refreshed list reaches the ViewModels.
  final UpdateRestaurantFacade viewModelFacade = UpdateRestaurantFacade();

  /// Also inbound: tells this monitor the tourist has moved.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  // ---------------------------------------------------------------------------
  // Watching for map data other tourists added (UC300, C21)
  // ---------------------------------------------------------------------------
  //
  // A tourist submits a landmark and everyone else's map is quietly stale. This
  // is what notices. It only *notices* - the dashboard asks before refreshing,
  // because re-fetching under someone's fingers while they are reading a pin is
  // worse than being a minute out of date.

  /// How often to check. Long, on purpose: landmarks are submitted in ones and
  /// twos, and this runs for as long as the app is open.
  static const Duration pollInterval = Duration(minutes: 2);

  Timer? _poll;
  MapDataStamp _lastSeen = MapDataStamp.empty;
  bool _checking = false;

  /// Starts polling. Safe to call more than once. The first check establishes
  /// the baseline without prompting - the tourist has only just opened the map,
  /// so nothing is stale yet.
  Future<void> start() async {
    stop();
    _lastSeen = await repository.map.mapDataStamp();
    _poll = Timer.periodic(pollInterval, (_) => _check());
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _check() async {
    // A slow poll must not stack behind itself.
    if (_checking) return;
    _checking = true;
    try {
      final MapDataStamp current = await repository.map.mapDataStamp();

      // A failed poll reads as empty. Treat that as "no news", never as
      // "everything was deleted".
      if (current.landmarkCount == 0 && current.restaurantCount == 0) return;

      final int newLandmarks = current.landmarkCount - _lastSeen.landmarkCount;
      final bool changed =
          current.landmarkCount != _lastSeen.landmarkCount ||
          current.restaurantCount != _lastSeen.restaurantCount;
      if (!changed) return;

      _lastSeen = current;
      viewModelFacade.publishMapDataChanged(
        newLandmarks: newLandmarks > 0 ? newLandmarks : 0,
      );
    } finally {
      _checking = false;
    }
  }
}
