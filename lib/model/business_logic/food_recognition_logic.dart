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

  /// Whether the PHOTO was too poor to trust the recognition from it -
  /// blurry, too dark/bright, or strongly colour-cast (see
  /// `GeminiLandmarkService`'s image-quality prompt block, which reports
  /// what it sees; deciding what that MEANS is this layer's job, which is
  /// why the threshold is here and not in the prompt or the widget).
  ///
  /// Deliberately only "poor" - "acceptable" is explicitly still usable, so
  /// a slightly-imperfect photo doesn't nag the tourist.
  bool isPoorImageQuality(String imageQuality) => imageQuality == 'poor';

  /// Whether the "is this Malaysian local food" judgement itself was too
  /// shaky to act on confidently, independent of how sure Gemini was about
  /// the dish NAME (see `FoodAnalysisResponse.localFoodConfidence` for why
  /// those are genuinely different questions). Uses the same bar as
  /// [isLowConfidence] - a borderline local-food call deserves the same
  /// "please verify" treatment as a borderline dish ID.
  bool isLowLocalFoodConfidence(double localFoodConfidence) =>
      localFoodConfidence < _lowConfidence;

  /// Whether the OS camera permission is granted, asking for it if not - the
  /// gate before the camera preview opens on `FoodRecognitionView` (REQ106_1).
  /// Routed through the repository so no View ever touches
  /// `permission_handler` directly.
  Future<bool> requestCameraPermission() =>
      discoveryRepository.camera.requestCameraPermission();

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
        localFoodConfidence: analysis.localConfidence,
        imageQuality: analysis.imageQuality,
        imageQualityIssues: analysis.imageQualityIssues,
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
    double localFoodConfidence = quick.localFoodConfidence;
    String imageQuality = quick.imageQuality;
    List<String> imageQualityIssues = quick.imageQualityIssues;
    if (candidates.length > 1) {
      result = candidates.take(3).toList(growable: false);
    } else {
      // "Confident" single result. The cheap catalogue-match path is only
      // trusted when the quick call is HIGHLY confident AND the photo itself
      // was usable - a shaky name, or a name read off a blurry/dark photo,
      // must never be matched to a catalogue record and shown as certain.
      // Anything less is re-judged by the full analysis, which is the
      // deeper, authoritative call.
      final LocalFood? existing = await foodRepository.knowledge.findByName(
        quick.dish,
      );
      if (existing != null &&
          quick.confidence >= _highConfidence &&
          !isPoorImageQuality(quick.imageQuality)) {
        result = <LocalFood>[existing];
      } else {
        final analysis = await discoveryRepository.recognition.analyzeFoodFull(
          imageBytes,
        );
        result = <LocalFood>[analysis.food];
        priceMin = analysis.priceMin;
        priceMax = analysis.priceMax;
        confidence = analysis.confidence;
        localFoodConfidence = analysis.localConfidence;
        imageQuality = analysis.imageQuality;
        imageQualityIssues = analysis.imageQualityIssues;
      }
    }

    return FoodRecognitionResult(
      isLocalFood: true,
      candidates: result,
      priceMin: priceMin,
      priceMax: priceMax,
      confidence: confidence,
      localFoodConfidence: localFoodConfidence,
      imageQuality: imageQuality,
      imageQualityIssues: imageQualityIssues,
    );
  }

  /// Manual fallback when Gemini's candidates don't include the right dish
  /// (the "type the food name" escape hatch on the result popup). VERIFIES the
  /// typed [name] against the photo - the user may be wrong, and a typed name
  /// must never be accepted on the user's say-so alone.
  ///
  /// Always sends the typed name AND the captured image to Gemini
  /// (`RecognitionRepository.analyzeFoodByName`) to check the claim first
  /// (decision: "always verify", not a catalogue fast-path). Only once the
  /// photo is verified to show the typed name is the curated catalogue row
  /// preferred for the details; otherwise what Gemini actually saw
  /// ([..observedFood]) comes back so the UI can warn instead of silently
  /// accepting a mismatched landmark.
  Future<
    ({
      LocalFood food,
      double priceMin,
      double priceMax,
      bool nameMatchesPhoto,
      double matchConfidence,
      bool isLocalFood,
      String observedFood,
    })
  >
  resolveByName(List<int> imageBytes, String name) async {
    final String trimmed = name.trim();
    final analysis = await discoveryRepository.recognition.analyzeFoodByName(
      imageBytes,
      trimmed,
    );
    LocalFood food = analysis.food;
    double priceMin = analysis.priceMin;
    double priceMax = analysis.priceMax;
    // The catalogue lookup is a details optimisation, never a substitute for
    // checking the photo - it only fills in the (more reliable) curated
    // details once Gemini has confirmed the typed name is what the photo
    // actually shows.
    if (analysis.nameMatchesPhoto) {
      final LocalFood? match = await foodRepository.knowledge.findByName(
        trimmed,
      );
      if (match != null) {
        food = match;
        priceMin = 0;
        priceMax = 0;
      }
    }
    return (
      food: food,
      priceMin: priceMin,
      priceMax: priceMax,
      nameMatchesPhoto: analysis.nameMatchesPhoto,
      matchConfidence: analysis.matchConfidence,
      isLocalFood: analysis.isLocal,
      observedFood: analysis.observedFood,
    );
  }

  /// Enriches a candidate the tourist picked from the top-3 picker (A5).
  /// These candidates came FROM the photo, so no name-vs-photo verification
  /// is needed - this just fills in full details: the catalogue row if there
  /// is one, else a Gemini name+image analysis of the picked dish.
  Future<({LocalFood food, double priceMin, double priceMax})> enrichCandidate(
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
