import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/food_analysis_response.dart';
import '../data_models/signboard_analysis_response.dart';
import '../data_models/stall_analysis_response.dart';

/// A recognised food plus Gemini's suggested MYR price range for it. The
/// repository surfaces both because the range is a property of the submitted
/// `LandmarkItem` (`landmark_item.price_min`/`price_max`), not of the shared
/// `local_food` catalogue.
/// A recognised food plus Gemini's suggested MYR price range for it and the
/// full analysis's local-food judgement. The repository surfaces both the
/// price range and `isLocal` because they're properties of the submitted
/// `LandmarkItem` / the local-food gate (`landmark_item.price_min` /
/// `price_max`), NOT of the shared `local_food` catalogue.
typedef FoodAnalysis = ({
  LocalFood food,
  double priceMin,
  double priceMax,

  /// Whether the FULL analysis judged this to be Malaysian local food - more
  /// reliable than the quick name-only call, so `FoodRecognitionLogic`
  /// trusts THIS when the two disagree (e.g. a Ramly burger the quick call
  /// mistook for a non-Malaysian dish).
  bool isLocal,

  /// How confident (0..1) the full analysis is in [food] - surfaced so a
  /// shaky result is never presented as certain.
  double confidence,
});

/// Food recognition from a photo, via Gemini. Also used for restaurant
/// signboard / stall image analysis (UC500) - one shared "send an image to
/// Gemini" repository, reused for a few different prompts by
/// `FoodRecognitionLogic` and `LandmarkSubmissionLogic`.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above -
/// see [analyzeFoodFull], which is where `FoodAnalysisResponse` (data model)
/// becomes `LocalFood` (domain model). That conversion used to live in
/// `FoodRecognitionLogic` instead; moved here to actually follow that rule.
///
/// Calls `api.geminiLandmark` (`GeminiLandmarkService`), not `api.gemini`
/// directly - the actual prompts live there, not on the generic
/// `GeminiService`, which stays reusable by other features.
class RecognitionRepository {
  RecognitionRepository();

  final APIManager api = APIManager();

  /// Quick, name-only call - phase 1 of the two-phase food recognition flow.
  /// Stays as the raw `FoodAnalysisResponse` (data model) rather than a
  /// domain model - `FoodRecognitionLogic` only inspects its status fields
  /// to decide whether to escalate to [analyzeFoodFull], it never treats
  /// this as a real food entity.
  Future<FoodAnalysisResponse> identifyFoodName(List<int> imageBytes) =>
      api.geminiLandmark.identifyFoodName(imageBytes: imageBytes);

  /// Full call - phase 2, only reached when the dish isn't already in the
  /// catalogue (`FoodKnowledgeRepository`). Returns the domain `LocalFood`
  /// directly, built here from Gemini's `FoodAnalysisResponse`.
  Future<FoodAnalysis> analyzeFoodFull(List<int> imageBytes) async {
    final FoodAnalysisResponse response = await api.geminiLandmark
        .analyzeFoodImage(imageBytes: imageBytes);
    return (
      food: _toLocalFood(response),
      priceMin: response.priceMin,
      priceMax: response.priceMax,
      isLocal: response.isMalaysianLocalFood,
      confidence: response.confidence,
    );
  }

  /// Full call with the tourist's typed dish name - phase 2 of the manual
  /// "type the food name" fallback (see `FoodRecognitionLogic.resolveByName`).
  /// Sends the name AND the image to Gemini so it verifies the photo against
  /// that name and returns the details for exactly that one dish (see
  /// `GeminiLandmarkService.analyzeFoodWithName`). The resulting `LocalFood`
  /// is always named exactly [name] - what the tourist typed - never a
  /// candidate list.
  Future<FoodAnalysis> analyzeFoodByName(
    List<int> imageBytes,
    String name,
  ) async {
    final FoodAnalysisResponse response = await api.geminiLandmark
        .analyzeFoodWithName(imageBytes: imageBytes, name: name);
    return (
      food: _toLocalFood(response, name: name),
      priceMin: response.priceMin,
      priceMax: response.priceMax,
      isLocal: response.isMalaysianLocalFood,
      confidence: response.confidence,
    );
  }

  /// `FoodAnalysisResponse` (data model) -> `LocalFood` (domain model) - the
  /// only place this conversion lives. [name] overrides the dish field when
  /// the caller supplied its own name (the manual-entry path).
  LocalFood _toLocalFood(FoodAnalysisResponse response, {String? name}) =>
      LocalFood(
        id: 0, // Not yet saved - a repository assigns this once persisted.
        name: name ?? response.dish,
        description: response.description,
        origin: response.origin,
        culturalBackground: response.culturalBackground,
        ingredients: '', // Not returned by Gemini yet
        category: response.foodCategory,
        cookingStyle: response.cookingStyle,
        mealType: response.mealType,
        foodType: 'Food', // Gemini doesn't classify food_type yet.
        synonyms: response.variant.isEmpty
            ? const <String>[]
            : <String>[response.variant],
      );

  /// Restaurant signboard photo - extracts the name (UC500, A7/A19).
  Future<SignboardAnalysisResponse> analyzeSignboard(List<int> imageBytes) =>
      api.geminiLandmark.analyzeSignboardImage(imageBytes: imageBytes);

  /// Stall photo - frame validation only, no auto-fill (UC500, A8/A15).
  Future<StallAnalysisResponse> analyzeStall(List<int> imageBytes) =>
      api.geminiLandmark.analyzeStallImage(imageBytes: imageBytes);
}
