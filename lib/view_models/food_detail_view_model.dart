import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/food_pairing.dart';
import '../domain_model/local_food.dart';
import '../domain_model/pronunciation_playback_result.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Presentation state for one local-food detail page.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel({this.foodId = 1});

  @protected
  FoodLogicFacade createFoodLogic() => FoodLogicFacade();

  late final FoodLogicFacade foodLogic = createFoodLogic();

  int foodId;
  LocalFood? _food;
  bool _isLiked = false;
  List<LocalFood> _similarFoods = const <LocalFood>[];
  List<LocalFood> _catalogue = const <LocalFood>[];
  List<FoodPairing> _pairings = const <FoodPairing>[];
  bool _loadingPairings = false;
  String? _pairingError;
  List<String> _allergyWarnings = const <String>[];
  LocalFood? _collidedFood;
  bool _isFoodInformationExpanded = false;
  bool _isStartingPronunciation = false;
  bool _isUpdatingFavourite = false;
  String? _pronunciationMessage;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  List<LocalFood> get similarFoods => _similarFoods;
  List<FoodPairing> get pairings => _pairings;
  bool get loadingPairings => _loadingPairings;
  String? get pairingError => _pairingError;
  List<String> get allergyWarnings => _allergyWarnings;
  LocalFood? get collidedFood => _collidedFood;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;
  bool get isStartingPronunciation => _isStartingPronunciation;
  bool get isUpdatingFavourite => _isUpdatingFavourite;
  String? get pronunciationMessage => _pronunciationMessage;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) async {
    await runGuarded(() async {
      foodId = id;
      _isFoodInformationExpanded = false;
      _pairings = const <FoodPairing>[];
      _pairingError = null;
      _food = await foodLogic.getFoodDetails(id);
      _isLiked = await foodLogic.isFoodInFavourites(id);
      _collidedFood = await foodLogic.detectNameCollision(id);
      _allergyWarnings = await foodLogic.dietaryWarnings(id);
      _similarFoods = await foodLogic.getSimilarFoods(id);
      _catalogue = await foodLogic.getLocalFoods();
    });
    if (_food != null && foodId == id) await loadPairings();
  }

  Future<void> loadPairings() async {
    if (_loadingPairings || _food == null) return;
    _loadingPairings = true;
    _pairingError = null;
    safeNotifyListeners();
    try {
      _pairings = await foodLogic.getFoodPairingRecommendations(foodId);
    } catch (error) {
      _pairings = const <FoodPairing>[];
      _pairingError = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _loadingPairings = false;
      safeNotifyListeners();
    }
  }

  LocalFood? pairedFood(int id) {
    for (final LocalFood food in _catalogue) {
      if (food.id == id) return food;
    }
    return null;
  }

  Future<String?> toggleLike() async {
    if (_isUpdatingFavourite) return null;
    _isUpdatingFavourite = true;
    safeNotifyListeners();
    try {
      _isLiked = await foodLogic.toggleFavouriteFood(foodId);
      _food = _food?.copyWith(isFavourite: _isLiked);
      return null;
    } catch (error) {
      final String message = error.toString();
      return message.startsWith('Exception: ')
          ? message.substring('Exception: '.length)
          : message;
    } finally {
      _isUpdatingFavourite = false;
      safeNotifyListeners();
    }
  }

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
          'Using your device voice for this pronunciation.',
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
}
