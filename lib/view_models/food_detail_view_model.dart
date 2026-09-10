import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../domain_model/pronunciation_playback_result.dart';
import '../model/business_logic/food_logic_facade.dart';

/// Presentation state for one local-food detail page.
///
/// Pairing & similar-food recommendations are rendered by the embedded
/// `FoodRecommendationView` (its own ViewModel), not owned here.
class FoodDetailViewModel extends BaseViewModel {
  FoodDetailViewModel();

  @protected
  FoodLogicFacade createFoodLogic() => FoodLogicFacade();

  late final FoodLogicFacade foodLogic = createFoodLogic();

  int foodId = 0;
  int _loadGeneration = 0;
  LocalFood? _food;
  bool _isLiked = false;
  String? _allergyWarning;
  LocalFood? _collidedFood;
  bool _isFoodInformationExpanded = false;
  bool _isStartingPronunciation = false;
  bool _isUpdatingFavourite = false;
  String? _pronunciationMessage;

  LocalFood? get food => _food;
  bool get isLiked => _isLiked;
  String? get allergyWarning => _allergyWarning;
  LocalFood? get collidedFood => _collidedFood;
  bool get isFoodInformationExpanded => _isFoodInformationExpanded;
  bool get isStartingPronunciation => _isStartingPronunciation;
  bool get isUpdatingFavourite => _isUpdatingFavourite;
  String? get pronunciationMessage => _pronunciationMessage;

  @override
  Future<void> onInit() => loadFood(foodId);

  Future<void> loadFood(int id) async {
    final int generation = ++_loadGeneration;
    foodId = id;
    _food = null;
    _isLiked = false;
    _collidedFood = null;
    _allergyWarning = null;
    _isFoodInformationExpanded = false;
    _isStartingPronunciation = false;
    _isUpdatingFavourite = false;
    _pronunciationMessage = null;
    setBusy();
    try {
      final LocalFood food = await foodLogic.getFoodDetails(id);
      final List<Object?> related = await Future.wait<Object?>(
        <Future<Object?>>[
          _orDefault<bool>(foodLogic.isFoodInFavourites(id), food.isFavourite),
          _orDefault<LocalFood?>(foodLogic.detectNameCollision(id), null),
          _dietaryWarningOrCaution(id),
        ],
      );
      if (generation != _loadGeneration) return;

      _isLiked = related[0] as bool;
      _food = food.copyWith(isFavourite: _isLiked);
      _collidedFood = related[1] as LocalFood?;
      _allergyWarning = related[2] as String?;
      setReady();
    } catch (error, stackTrace) {
      if (generation == _loadGeneration) setError(error, stackTrace);
    }
  }

  Future<T> _orDefault<T>(Future<T> request, T fallback) async {
    try {
      return await request;
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> _dietaryWarningOrCaution(int id) async {
    try {
      return await foodLogic.dietaryWarning(id);
    } catch (_) {
      return 'Dietary information is unavailable. Check with the restaurant '
          'before ordering.';
    }
  }

  Future<String?> toggleLike() async {
    if (_isUpdatingFavourite) return null;
    final int requestedFoodId = foodId;
    final int generation = _loadGeneration;
    _isUpdatingFavourite = true;
    safeNotifyListeners();
    try {
      final bool isLiked = await foodLogic.toggleFavouriteFood(requestedFoodId);
      if (generation != _loadGeneration ||
          (_food != null && _food!.id != requestedFoodId)) {
        return null;
      }
      _isLiked = isLiked;
      _food = _food?.copyWith(isFavourite: isLiked);
      return null;
    } catch (error) {
      if (generation != _loadGeneration) return null;
      final String message = error.toString();
      return message.startsWith('Exception: ')
          ? message.substring('Exception: '.length)
          : message;
    } finally {
      if (generation == _loadGeneration) {
        _isUpdatingFavourite = false;
        safeNotifyListeners();
      }
    }
  }

  void toggleFoodInformation() {
    _isFoodInformationExpanded = !_isFoodInformationExpanded;
    safeNotifyListeners();
  }

  Future<void> playPronunciation() async {
    final LocalFood? currentFood = _food;
    if (currentFood == null || _isStartingPronunciation) return;
    final int generation = _loadGeneration;
    _isStartingPronunciation = true;
    _pronunciationMessage = null;
    safeNotifyListeners();
    try {
      final PronunciationPlaybackResult result = await foodLogic
          .playPronunciation(currentFood);
      if (generation != _loadGeneration || _food?.id != currentFood.id) return;
      _pronunciationMessage = switch (result) {
        PronunciationPlaybackResult.curatedAudio => null,
        PronunciationPlaybackResult.deviceVoice =>
          'Using your device voice for this pronunciation.',
        PronunciationPlaybackResult.unavailable =>
          'Pronunciation audio is unavailable on this device.',
      };
    } finally {
      if (generation == _loadGeneration) {
        _isStartingPronunciation = false;
        safeNotifyListeners();
      }
    }
  }

  String? takePronunciationMessage() {
    final String? message = _pronunciationMessage;
    _pronunciationMessage = null;
    return message;
  }
}
