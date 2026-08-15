import '../facades/discovery_logic_facade.dart';
import '../../repositories/facades/map_repository.dart';
import '../../repositories/facades/location_repository.dart';

class MapExplorationLogic implements DiscoveryLogicFacade {
  final MapRepository mapRepository;
  final LocationRepository locationRepository;

  MapExplorationLogic({
    required this.mapRepository,
    required this.locationRepository,
  });

  // TODO: Implement MapExplorationLogic by coordinating repository facades only.
}
