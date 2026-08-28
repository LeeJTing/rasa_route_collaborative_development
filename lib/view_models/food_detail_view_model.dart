import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Presentation state for one local-food detail page.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel({this.foodId = 1});

  final FoodLogicFacade foodLogic = FoodLogicFacade();

  int foodId;
  LocalFood? _food;
  bool _isLiked = false;
  List<LocalFood> _similarFoods = const <LocalFood>[];
  List<String> _allergyWarnings = const <String>[];
  LocalFood? _collidedFood;
  bool _isFoodInformationExpanded = false;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<String> get allergyWarnings => _allergyWarnings;
  LocalFood? get collidedFood => _collidedFood;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) => runGuarded(() async {
    foodId = id;
    _isFoodInformationExpanded = false;
    _food = await foodLogic.getFoodDetails(id);
    _isLiked = await foodLogic.isFoodInFavourites(id);
    _collidedFood = await foodLogic.detectNameCollision(id);
    _allergyWarnings = await foodLogic.detectAllergies(_food!);
    _similarFoods = await foodLogic.getSimilarFoods(id);
  });

  Future<void> toggleLike() => runGuarded(() async {
    await foodLogic.toggleFavouriteFood(foodId);
    _isLiked = !_isLiked;
    _food = _food?.copyWith(isFavourite: _isLiked);
  }, silent: true);

  void toggleFoodInformation() {
    _isFoodInformationExpanded = !_isFoodInformationExpanded;
    safeNotifyListeners();
  }
}
