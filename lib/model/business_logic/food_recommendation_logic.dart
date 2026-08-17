import '../repositories/food_repository_facade.dart';

/// Ranks dishes for a tourist and drives the swipe deck.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodRecommendationLogic {
  FoodRecommendationLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();
}
