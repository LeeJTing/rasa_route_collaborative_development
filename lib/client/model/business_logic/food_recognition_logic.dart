import '../facades/discovery_logic_facade.dart';
import '../../repositories/facades/recognition_repository.dart';
import '../../repositories/facades/food_repository_facade.dart';

class FoodRecognitionLogic implements DiscoveryLogicFacade {
  final RecognitionRepository recognitionRepository;
  final FoodRepository foodRepository;

  FoodRecognitionLogic({
    required this.recognitionRepository,
    required this.foodRepository,
  });

  // TODO: Implement FoodRecognitionLogic by coordinating repository facades only.
}
