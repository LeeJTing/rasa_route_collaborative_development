import '../repositories/discovery_repository_facade.dart';

/// Connecting a dish to the places that serve it.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodDiscoveryLogic {
  FoodDiscoveryLogic();

  final DiscoveryRepositoryFacade repository = DiscoveryRepositoryFacade();
}
