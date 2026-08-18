import 'food_comparison_logic.dart';
import 'food_knowledge_logic.dart';
import 'food_recommendation_logic.dart';

/// Dishes: catalogue, favourites, comparison and recommendation. Used by the
/// LocalFoodList, FoodDetail, FoodComparison, FoodRecommendation and
/// FavouriteCollection ViewModels.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
class FoodLogicFacade {
  FoodLogicFacade();

  final FoodKnowledgeLogic knowledge = FoodKnowledgeLogic();
  final FoodComparisonLogic comparison = FoodComparisonLogic();
  final FoodRecommendationLogic recommendation = FoodRecommendationLogic();
}
