import '../repositories/discovery_repository_facade.dart';

/// Finding and filtering restaurants.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class RestaurantDiscoveryLogic {
  RestaurantDiscoveryLogic();

  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();
}
