import '../core/base_view_model.dart';
import '../domain_model/food_pairing.dart';
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
  List<FoodPairing> _foodPairings = const <FoodPairing>[];
  List<String> _allergyWarnings = const <String>[];
  LocalFood? _collidedFood;
  bool _pairingTimedOut = false;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<FoodPairing> get foodPairings => _foodPairings;
  List<String> get allergyWarnings => _allergyWarnings;
  LocalFood? get collidedFood => _collidedFood;
  bool get pairingTimedOut => _pairingTimedOut;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) => runGuarded(() async {
    foodId = id;
    _pairingTimedOut = false;
    _food = await foodLogic.getFoodDetails(id);
    _isLiked = await foodLogic.isFoodInFavourites(id);
    _collidedFood = await foodLogic.detectNameCollision(id);
    _allergyWarnings = await foodLogic.detectAllergies(_food!);
    _similarFoods = await foodLogic.getSimilarFoods(id);
    await _loadPairings();
  });

  Future<void> toggleLike() => runGuarded(() async {
    await foodLogic.toggleFavouriteFood(foodId);
    _isLiked = !_isLiked;
    _food = _food?.copyWith(isFavourite: _isLiked);
  }, silent: true);

  Future<void> retryPairings() => runGuarded(_loadPairings, silent: true);

  Future<void> _loadPairings() async {
    _pairingTimedOut = false;
    try {
      _foodPairings = await foodLogic
          .getFoodPairingRecommendations(foodId)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      _foodPairings = const <FoodPairing>[];
      _pairingTimedOut = true;
    }
  }
}
