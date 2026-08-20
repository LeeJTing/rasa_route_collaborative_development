import '../repositories/discovery_repository_facade.dart';
import '../repositories/food_repository_facade.dart';

/// Photo -> Gemini -> a row in `local_food`.
/// The one logic class holding two repository facades: it recognises through
/// one and resolves the label against the catalogue through the other.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodRecognitionLogic {
  FoodRecognitionLogic();

  final DiscoveryRepositoryFacade discoveryRepository =
      DiscoveryRepositoryFacade();
  final FoodRepositoryFacade foodRepository = FoodRepositoryFacade();
}
