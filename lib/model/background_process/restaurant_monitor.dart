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
}
