import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/food_recognition_result.dart';
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
  FoodRecognitionLogic({
    @visibleForTesting DiscoveryRepositoryFacade? discoveryRepository,
    @visibleForTesting FoodRepositoryFacade? foodRepository,
  }) : discoveryRepository = discoveryRepository ?? DiscoveryRepositoryFacade(),
       foodRepository = foodRepository ?? FoodRepositoryFacade();

  /// A single quick-call result is only trusted - and allowed to shortcut
  /// straight to a catalogue record - at or above this confidence (0..1).
  /// Below it the full analysis re-judges the photo instead (ACCURACY: a
  /// shaky name must never be matched to a catalogue row and shown as
  /// certain).
  static const double _highConfidence = 0.8;

  /// Below this confidence (0..1) a recognition is shaky enough that the
  /// tourist should be asked to verify it - see [isLowConfidence]. Distinct
  /// from [_highConfidence], which decides whether the cheap catalogue
  /// shortcut is trusted at all: a result can clear this bar (so no warning
  /// is shown) while still being re-judged by the full analysis.
  static const double _lowConfidence = 0.6;

  /// Whether [confidence] (0..1) is shaky enough that the result should be
  /// flagged for the tourist to verify rather than presented as certain.
  ///
  /// A domain rule about what counts as trustworthy recognition, not
  /// styling - so the threshold lives here beside [_highConfidence] rather
  /// than inline in the widget that renders the warning. `RecognitionResultCard`
  /// takes the ALREADY-DECIDED boolean (`isLowConfidence`) as a parameter
  /// and only chooses how to draw it.
  bool isLowConfidence(double confidence) => confidence < _lowConfidence;

  final DiscoveryRepositoryFacade discoveryRepository;
  final FoodRepositoryFacade foodRepository;

  /// Recognises the food in [imageBytes] (REQ106_2, UC500 two-phase flow):
  ///  1. A quick, name-only Gemini call (`RecognitionRepository.identifyFoodName`).
  ///  2. If that name is already in the catalogue (`FoodKnowledgeRepository`),
  ///     the stored record is used as-is - no need to pay for a full call.
  ///  3. Otherwise, a second, full Gemini call generates the complete entry
  ///     (`RecognitionRepository.analyzeFoodFull`, already returning the
  ///     domain `LocalFood` directly).
  ///
  /// Returns a [FoodRecognitionResult]:
  ///   * `candidates.length == 1` - a confident single result;
  ///   * `candidates.length == 2..3` - Gemini was unsure between a few likely
  ///     dishes, surfaced as a top-3 picker (A5) in the order Gemini returned
  ///     them (most likely first). A candidate that isn't in the catalogue is
  ///     still shown name-only, so it can be picked instead of silently
  ///     disappearing;
  ///   * `isLocalFood == false` - the photo is NOT Malaysian local food. The
  ///     details are still returned (full analysis, so "View Details" has
  ///     something to show) but the caller must NOT let the tourist add it as
  ///     a landmark.
  ///
  /// Throws on A4 (no food detected), A18 (image incomplete) or multi-food
  /// (more than one dish in frame) - callers already catch around Gemini
  /// calls for A2 (timeout), so surfacing these the same way keeps one error
  /// path. A3 (not local food) is NO LONGER an error - see
  /// [FoodRecognitionResult] for how it's surfaced instead.
  Future<FoodRecognitionResult> recognizeFood(List<int> imageBytes) async {
    final quick = await discoveryRepository.recognition.identifyFoodName(
      imageBytes,
    );

    if (quick.foodStatus == 'not_detected') {
      throw Exception('No food detected in image. Please try again.');
    }
    if (quick.foodImageStatus != 'complete') {
      throw Exception("Image not complete, ensure it's in frame.");
    }
    // More than one distinct dish in frame - the tourist should re-capture
    // with only one food (instead of the app listing every dish found).
    if (quick.foodCount > 1) {
      throw Exception('Please capture only one food in the frame.');
    }

    // Not Malaysian local food (per the quick call): show its details (full
    // analysis so "View Details" has real information), but the quick call's
    // "not local" judgement is PROVISIONAL - it can under-rate a Malaysian
    // street-food adaptation (e.g. a Ramly burger, judged "not local" just
    // because the word "burger" sounds Western). The full analysis examines
    // the dish in depth and returns its own `isMalaysianLocalFood` - trust
    // THAT here, so a genuinely Malaysian dish is still addable as a landmark
    // while a genuinely non-Malaysian one stays hidden behind the gate.
    if (!quick.isMalaysianLocalFood) {
      final analysis = await discoveryRepository.recognition.analyzeFoodFull(
        imageBytes,
      );
      return FoodRecognitionResult(
        isLocalFood: analysis.isLocal,
        candidates: <LocalFood>[analysis.food],
        priceMin: analysis.priceMin,
        priceMax: analysis.priceMax,
        confidence: analysis.confidence,
      );
    }

    // Single food, but Gemini is unsure between a few likely dishes: keep the
    // top-3 candidates in the order Gemini returned (most likely first, so
    // already confidence-ordered), resolving each against the catalogue. A
    // candidate that isn't in the catalogue is still offered name-only so the
    // tourist can pick it (A5) instead of it silently disappearing.
    final List<LocalFood> candidates = <LocalFood>[];
    for (final candidate in quick.candidates) {
      if (candidate.confidence < 0.5) continue;
      final LocalFood? match = await foodRepository.knowledge.findByName(
        candidate.dish,
      );
      final LocalFood food =
          match ?? _nameOnlyFood(candidate.dish, quick.foodCategory);
      if (!candidates.any((LocalFood f) => f.name == food.name)) {
        candidates.add(food);
      }
    }

    final List<LocalFood> result;
    double priceMin = 0;
    double priceMax = 0;
    // Confidence of whatever produced the single result - the quick call for
    // a catalogue hit, the full analysis otherwise. Low values are surfaced
    // in the UI so a shaky result is never presented as certain.
    double confidence = quick.confidence;
    if (candidates.length > 1) {
      result = candidates.take(3).toList(growable: false);
    } else {
      // "Confident" single result. The cheap catalogue-match path is only
      // trusted when the quick call is HIGHLY confident - a shaky name must
      // never be matched to a catalogue record and shown as certain. Anything
      // less than that (or not in the catalogue) is re-judged by the full
      // analysis, which is the deeper, authoritative call.
      final LocalFood? existing = await foodRepository.knowledge.findByName(
        quick.dish,
      );
      if (existing != null && quick.confidence >= _highConfidence) {
        result = <LocalFood>[existing];
      } else {
        final analysis = await discoveryRepository.recognition.analyzeFoodFull(
          imageBytes,
        );
        result = <LocalFood>[analysis.food];
        priceMin = analysis.priceMin;
        priceMax = analysis.priceMax;
        confidence = analysis.confidence;
      }
    }

    return FoodRecognitionResult(
      isLocalFood: true,
      candidates: result,
      priceMin: priceMin,
      priceMax: priceMax,
      confidence: confidence,
    );
  }

  /// Manual fallback when Gemini's candidates don't include the right dish
  /// (the "type the food name" escape hatch on the result popup):
  ///   * if [name] is in the catalogue, the stored record is used as-is
  ///     (full details, no Gemini cost);
  ///   * otherwise the typed [name] AND the captured image are sent to Gemini
  ///     together (`RecognitionRepository.analyzeFoodByName`) - it verifies
  ///     the photo against the name and returns the details for exactly that
  ///     one dish, so the result is always the food the tourist named.
  Future<({LocalFood food, double priceMin, double priceMax})> resolveByName(
    List<int> imageBytes,
    String name,
  ) async {
    final String trimmed = name.trim();
    final LocalFood? match = await foodRepository.knowledge.findByName(trimmed);
    if (match != null) return (food: match, priceMin: 0.0, priceMax: 0.0);
    final analysis = await discoveryRepository.recognition.analyzeFoodByName(
      imageBytes,
      trimmed,
    );
    return (
      food: analysis.food,
      priceMin: analysis.priceMin,
      priceMax: analysis.priceMax,
    );
  }

  /// A candidate from the quick call that isn't in the catalogue, reduced to
  /// a name-only `LocalFood` so the top-3 picker can still offer it. The
  /// full details come from a later full analysis once the tourist picks it.
  LocalFood _nameOnlyFood(String name, String category) => LocalFood(
    id: 0, // Not saved yet - a repository assigns this once persisted.
    name: name,
    description: '',
    origin: '',
    culturalBackground: '',
    ingredients: '',
    category: category,
    cookingStyle: '',
    mealType: '',
    foodType: 'Food',
  );
}
