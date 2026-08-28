import '../core/base_view_model.dart';
import '../domain_model/food_pairing.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Presentation state for one local-food detail page.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel();

  final FoodLogicFacade foodLogic = FoodLogicFacade();

  static const Duration _pairingTimeout = Duration(seconds: 20);

  int foodId = 0;
  LocalFood? _food;
  bool _isLiked = false;
  List<LocalFood> _similarFoods = const <LocalFood>[];
  List<FoodPairing> _foodPairings = const <FoodPairing>[];
  List<String> _allergyWarnings = const <String>[];
  LocalFood? _collidedFood;
  bool _pairingTimedOut = false;
  bool _isFoodInformationExpanded = false;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<FoodPairing> get foodPairings => _foodPairings;
  List<String> get allergyWarnings => _allergyWarnings;
  LocalFood? get collidedFood => _collidedFood;
  bool get pairingTimedOut => _pairingTimedOut;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) => runGuarded(() async {
    if (id <= 0) throw Exception('No local food was selected.');
    foodId = id;
    _pairingTimedOut = false;
    _isFoodInformationExpanded = false;
    _food = await foodLogic.getFoodDetails(id);
    _isLiked = await foodLogic.isFoodInFavourites(id);
    _collidedFood = await foodLogic.detectNameCollision(id);
    _allergyWarnings = foodLogic.detectAllergies(_food!);
    _similarFoods = await foodLogic.getSimilarFoods(id);
    await _loadPairings();
  });

  Future<void> toggleLike() => runGuarded(() async {
    await foodLogic.toggleFavouriteFood(foodId);
    _isLiked = !_isLiked;
    final LocalFood? food = _food;
    if (food != null) _food = _withFavourite(food, _isLiked);
  }, silent: true);

  Future<void> retryPairings() => runGuarded(_loadPairings, silent: true);

  void toggleFoodInformation() {
    _isFoodInformationExpanded = !_isFoodInformationExpanded;
    safeNotifyListeners();
  }

  Future<void> _loadPairings() async {
    _pairingTimedOut = false;
    try {
      _foodPairings = await foodLogic
          .getFoodPairingRecommendations(foodId)
          .timeout(_pairingTimeout);
    } catch (_) {
      _foodPairings = const <FoodPairing>[];
      _pairingTimedOut = true;
    }
  }

  LocalFood _withFavourite(LocalFood food, bool isFavourite) => LocalFood(
    id: food.id,
    name: food.name,
    description: food.description,
    origin: food.origin,
    culturalBackground: food.culturalBackground,
    ingredients: food.ingredients,
    category: food.category,
    cookingStyle: food.cookingStyle,
    mealType: food.mealType,
    foodType: food.foodType,
    tastes: food.tastes,
    mainTaste: food.mainTaste,
    pronunciationText: food.pronunciationText,
    audioGuideUrl: food.audioGuideUrl,
    synonyms: food.synonyms,
    imageUrls: food.imageUrls,
    isFavourite: isFavourite,
  );
}
