import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/local_food.dart';
import '../repositories/food_repository_facade.dart';
import '../repositories/tourist_repository_facade.dart';

/// Canonical Food-module facts consumed by Discovery orchestration.
///
/// This keeps Food repositories owned by [FoodRepositoryFacade]; Discovery
/// business logic collaborates with this logic object instead of duplicating
/// those repositories in its own repository facade.
class DiscoveryFoodContextLogic {
  DiscoveryFoodContextLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();

  Future<List<LocalFood>> foods() => repository.getFoods();

  Future<List<FoodPreference>> preferences() =>
      repository.touristFoodPreferences();

  Future<List<DietaryRestriction>> dietaryRestrictions() =>
      repository.touristDietaryRestrictions();

  Future<Set<int>> favouriteFoodIds() => repository.favouriteFoodIds();

  Future<Map<int, List<int>>> restrictionIdsByFood() =>
      repository.foodDietaryRestrictionIds();
}

/// Canonical Tourist-module identity consumed by Discovery orchestration.
class DiscoveryTouristContextLogic {
  DiscoveryTouristContextLogic();

  final TouristRepositoryFacade repository = TouristRepositoryFacade();

  Future<String?> currentTouristId() => repository.currentTouristId();
}
