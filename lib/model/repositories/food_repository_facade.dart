import 'food_knowledge_repository.dart';
import 'recommendation_repository.dart';
import 'swipe_repository.dart';

/// Everything about dishes: the catalogue, favourites, recommendation candidates and the swipe deck.
///
/// REPOSITORY FACADE - a business-logic class holds ONE of these, not four
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes them as a single flat API. No business rules live here.
class FoodRepositoryFacade {
  FoodRepositoryFacade();

  final FoodKnowledgeRepository knowledge = FoodKnowledgeRepository();
  final RecommendationRepository recommendation = RecommendationRepository();
  final SwipeRepository swipe = SwipeRepository();
}
