import '../repositories/food_repository_facade.dart';

/// The food catalogue: browse, search, detail, pairings and similarity.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodKnowledgeLogic {
  FoodKnowledgeLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();
}
