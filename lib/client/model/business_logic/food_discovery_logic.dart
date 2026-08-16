import 'discovery_logic_facade.dart';
import '../repositories/food_repository_facade.dart';
import '../repositories/interaction_repository.dart';

class FoodDiscoveryLogic implements DiscoveryLogicFacade {
  final FoodRepository foodRepository;
  final InteractionRepository interactionRepository;

  FoodDiscoveryLogic({
    required this.foodRepository,
    required this.interactionRepository,
  });

  // TODO: Implement FoodDiscoveryLogic by coordinating repository facades only.
}
