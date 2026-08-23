import 'local_food.dart';

/// Outcome of `FoodRecognitionLogic.recognizeFood` - the up-to-3 candidate
/// foods to show the tourist, plus whether the photo actually shows a
/// Malaysian local food.
///
/// `isLocalFood == false` means Gemini judged the dish as NOT Malaysian local
/// food. The details are still shown (same "Recognised Food" card UI, and
/// "View Details" - A6 - still works) but the tourist must NOT be allowed to
/// add it as a landmark; the caller hides/guards the "Add New Landmark"
/// action in that case.
class FoodRecognitionResult {
  const FoodRecognitionResult({
    required this.isLocalFood,
    required this.candidates,
    this.priceMin = 0,
    this.priceMax = 0,
    this.confidence = 1.0,
  });

  /// Whether the photo shows a Malaysian local food.
  final bool isLocalFood;

  /// How confident (0..1) Gemini is in the single recognised food. Only
  /// meaningful for a single-result outcome (a full analysis or a high-
  /// confidence catalogue match); `1.0` when unknown (picker/manual entry).
  /// Low values are surfaced in the UI so a shaky result is never presented
  /// as certain.
  final double confidence;

  /// Suggested MYR price range for the recognised food, from Gemini's full
  /// analysis - carried onto the persisted `LandmarkItem`. Only known for a
  /// single recognised food (a confident full analysis or a manual name
  /// entry); `0` for catalogue-matched or picker candidates.
  final double priceMin;
  final double priceMax;

  /// 1..3 candidate foods:
  ///   * [isLocalFood] == true, length 1 - a confident single result;
  ///   * [isLocalFood] == true, length 2..3 - Gemini was unsure between a few
  ///     likely dishes, surfaced as a top-3 picker (A5) in confidence order;
  ///   * [isLocalFood] == false - exactly one (from the full analysis, so
  ///     "View Details" has real information), which must not be added as a
  ///     landmark.
  final List<LocalFood> candidates;
}
