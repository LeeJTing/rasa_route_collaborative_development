import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/food_analysis_response.dart';
import '../data_models/signboard_analysis_response.dart';
import '../data_models/stall_analysis_response.dart';

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
  Future<LocalFood> analyzeFoodFull(List<int> imageBytes) async {
    final FoodAnalysisResponse response = await api.geminiLandmark.analyzeFoodImage(
      imageBytes: imageBytes,
    );
    return LocalFood(
      id: 0, // Not yet saved - a repository assigns this once persisted.
      name: response.dish,
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
  }

  /// Restaurant signboard photo - extracts the name (UC500, A7/A19).
  Future<SignboardAnalysisResponse> analyzeSignboard(List<int> imageBytes) =>
      api.geminiLandmark.analyzeSignboardImage(imageBytes: imageBytes);

  /// Stall photo - frame validation only, no auto-fill (UC500, A8/A15).
  Future<StallAnalysisResponse> analyzeStall(List<int> imageBytes) =>
      api.geminiLandmark.analyzeStallImage(imageBytes: imageBytes);
}
