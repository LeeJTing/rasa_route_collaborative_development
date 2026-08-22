import '../../domain_model/local_food.dart';
import '../repositories/discovery_repository_facade.dart';
import '../repositories/food_repository_facade.dart';

/// Photo -> Gemini -> a row in `local_food`.
/// The one logic class holding two repository facades: it recognises through
/// one and resolves the label against the catalogue through the other.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter. It also
/// never builds a domain model itself from a data model - that conversion
/// belongs to the repository (see `RecognitionRepository.analyzeFoodFull`);
/// this class only orchestrates the two-phase *policy* of when to ask for
/// one.
class FoodRecognitionLogic {
  FoodRecognitionLogic();

  final DiscoveryRepositoryFacade discoveryRepository =
      DiscoveryRepositoryFacade();
  final FoodRepositoryFacade foodRepository = FoodRepositoryFacade();

  /// Recognises the food in [imageBytes] (REQ106_2, UC500 two-phase flow):
  ///  1. A quick, name-only Gemini call (`RecognitionRepository.identifyFoodName`).
  ///  2. If that name is already in the catalogue (`FoodKnowledgeRepository`),
  ///     the stored record is used as-is - no need to pay for a full call.
  ///  3. Otherwise, a second, full Gemini call generates the complete entry
  ///     (`RecognitionRepository.analyzeFoodFull`, already returning the
  ///     domain `LocalFood` directly).
  ///
  /// Returns a list of 1+ foods:
  ///   * length 1 - a confident single result;
  ///   * length 2..3 - Gemini was unsure between a few likely dishes, resolved
  ///     against the catalogue, surfaced as a top-3 picker (A5).
  ///
  /// Throws on A3 (not local food), A4 (no food detected), A18 (image
  /// incomplete) or multi-food (more than one dish in frame) - callers already
  /// catch around Gemini calls for A2 (timeout), so surfacing these the same
  /// way keeps one error path.
  Future<List<LocalFood>> recognizeFood(List<int> imageBytes) async {
    final quick = await discoveryRepository.recognition.identifyFoodName(
      imageBytes,
    );

    if (quick.foodStatus == 'not_detected') {
      throw Exception('No food detected in image. Please try again.');
    }
    if (quick.foodImageStatus != 'complete') {
      throw Exception("Image not complete, ensure it's in frame.");
    }
    if (!quick.isMalaysianLocalFood) {
      throw Exception('Not Malaysian local food. Please capture a local food.');
    }
    // More than one distinct dish in frame - the tourist should re-capture
    // with only one food (instead of the app listing every dish found).
    if (quick.foodCount > 1) {
      throw Exception('Please capture only one food in the frame.');
    }

    // Single food, but Gemini is unsure between a few likely dishes: resolve
    // the candidates against the catalogue and, if several match, surface
    // them as a top-3 picker for the tourist to choose from (A5).
    final List<LocalFood> candidates = <LocalFood>[];
    for (final candidate in quick.candidates) {
      if (candidate.confidence < 0.5) continue;
      final LocalFood? match = await foodRepository.knowledge.findByName(
        candidate.dish,
      );
      if (match != null &&
          !candidates.any((LocalFood f) => f.name == match.name)) {
        candidates.add(match);
      }
    }

    final List<LocalFood> result;
    if (candidates.length > 1) {
      result = candidates.take(3).toList(growable: false);
    } else {
      // Confident single result: catalogue match, else a full Gemini analysis.
      final LocalFood? existing = await foodRepository.knowledge.findByName(
        quick.dish,
      );
      result = existing != null
          ? <LocalFood>[existing]
          : <LocalFood>[
              await discoveryRepository.recognition.analyzeFoodFull(imageBytes),
            ];
    }

    return result;
  }
}
