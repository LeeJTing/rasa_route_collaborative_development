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
  bool _isStartingPronunciation = false;
  String? _pronunciationMessage;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<String> get allergyWarnings => _allergyWarnings;
  LocalFood? get collidedFood => _collidedFood;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;
  bool get isStartingPronunciation => _isStartingPronunciation;
  String? get pronunciationMessage => _pronunciationMessage;

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

  Future<void> playPronunciation() async {
    final LocalFood? currentFood = _food;
    if (currentFood == null || _isStartingPronunciation) return;
    _isStartingPronunciation = true;
    _pronunciationMessage = null;
    safeNotifyListeners();
    try {
      final PronunciationPlaybackResult result = await foodLogic
          .playPronunciation(currentFood);
      _pronunciationMessage = switch (result) {
        PronunciationPlaybackResult.curatedAudio => null,
        PronunciationPlaybackResult.deviceVoice =>
          'Using your device voice because the recorded audio is unavailable.',
        PronunciationPlaybackResult.unavailable =>
          'Pronunciation audio is unavailable on this device.',
      };
    } finally {
      _isStartingPronunciation = false;
      safeNotifyListeners();
    }
  }

  String? takePronunciationMessage() {
    final String? message = _pronunciationMessage;
    _pronunciationMessage = null;
    return message;
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
