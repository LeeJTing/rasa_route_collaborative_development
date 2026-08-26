import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Ranked food suggestions used by the recommendation screen.
class FoodRecommendationViewModel extends BaseViewModel {
  final FoodLogicFacade foodLogic = FoodLogicFacade();

  List<LocalFood> _recommendations = const <LocalFood>[];
  List<LocalFood> get recommendations => _recommendations;

  @override
  Future<void> onInit() => runGuarded(() async {
    _recommendations = await foodLogic.getLocalFoods();
  });
}
