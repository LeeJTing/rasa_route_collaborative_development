import '../repositories/food_repository_facade.dart';

/// Builds the side-by-side comparison of two or more dishes.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodComparisonLogic {
  FoodComparisonLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();
}
