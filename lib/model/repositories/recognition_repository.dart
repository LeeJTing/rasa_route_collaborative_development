import '../../domain_model/local_food.dart';
import '../../domain_model/origin_verification.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/food_analysis_response.dart';
import '../data_models/place_photo_match_response.dart';
import '../data_models/signboard_analysis_response.dart';
import '../data_models/signboard_name_match_response.dart';
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

  /// How confident (0..1) the full analysis is in [isLocal] SPECIFICALLY -
  /// separate from [confidence], which is about naming the dish. The two
  /// genuinely differ: a burger can be unmistakable as a burger while
  /// whether it's a Malaysian Ramly-style one stays a close call.
  double localConfidence,

  /// Usability of the PHOTO itself: "good" | "acceptable" | "poor".
  String imageQuality,

  /// Specific problems behind a non-"good" [imageQuality] - e.g.
  /// `["blurry", "too_dark"]`. Empty when the photo is fine.
  List<String> imageQualityIssues,

  /// Whether the photo plausibly shows the typed name (manual-entry path) -
  /// `FoodRecognitionLogic.resolveByName` uses this to decide whether a
  /// mismatch should be surfaced rather than silently accepted.
  bool nameMatchesPhoto,

  /// How sure (0..1) Gemini is of [nameMatchesPhoto]. `0` when not applicable.
  double matchConfidence,

  /// What the photo actually shows, in Gemini's words, when [nameMatchesPhoto]
  /// is false - the UI says "this photo looks more like X".
  String observedFood,

  /// The raw catalogue dish-type classification from Gemini ("Food" |
  /// "Beverage" | "Fruit" | "Dessert" | "Kuih" | "none" | ""). Carried raw
  /// so `FoodRecognitionLogic` can gate addability - a "none" item (snack,
  /// package, canned drink) is a Malaysian product at most, never an addable
  /// dish.
  String foodType,

  /// Dietary restrictions that apply to this dish, using the canonical
  /// `dietary_restriction.restriction_name` strings. Written to the
  /// `food_dietary_restriction` association table when the food is added to
  /// the catalogue - carried here (NOT on `LocalFood`) because dietary is an
  /// association, not a `local_food` column.
  List<String> dietaryRestrictions,
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
  ///
  /// [storedDish] is the curated row the app already matched for this dish,
  /// when there is one: it rides the prompt as the STORED CATALOGUE RECORD so
  /// the analysis answers with the dish AS SHOWN - the stored text echoed
  /// where it still holds, adapted where a variant changes it (see
  /// `GeminiLandmarkService._storedDishRules`).
  Future<FoodAnalysis> analyzeFoodFull(
    List<int> imageBytes, {
    LocalFood? storedDish,
  }) async {
    final FoodAnalysisResponse response = await api.geminiLandmark
        .analyzeFoodImage(
          imageBytes: imageBytes,
          storedDish: _storedDishPrompt(storedDish),
        );
    return (
      food: _toLocalFood(response),
      priceMin: response.priceMin,
      priceMax: response.priceMax,
      isLocal: response.isMalaysianLocalFood,
      confidence: response.confidence,
      localConfidence: response.localFoodConfidence,
      imageQuality: response.imageQuality,
      imageQualityIssues: response.imageQualityIssues,
      nameMatchesPhoto: response.nameMatchesPhoto,
      matchConfidence: response.matchConfidence,
      observedFood: response.observedFood,
      foodType: response.foodType,
      dietaryRestrictions: response.dietaryRestrictions,
    );
  }

  /// Full call with the tourist's typed dish name - phase 2 of the manual
  /// "type the food name" fallback (see `FoodRecognitionLogic.resolveByName`).
  /// Sends the name AND the image to Gemini so it verifies the photo against
  /// that name and returns the details for exactly that one dish (see
  /// `GeminiLandmarkService.analyzeFoodWithName`). The resulting `LocalFood`
  /// is named from `response.dish` - never the typed name forced onto it: on
  /// a match Gemini sets `dish` to the typed dish, on a mismatch it sets it
  /// to the dish it actually saw, so a food's name and its details always
  /// describe the same dish.
  ///
  /// [storedDish] is the curated row the typed name already matches, when
  /// there is one - its text rides the prompt as the STORED CATALOGUE RECORD,
  /// so a typed VARIANT comes back adapted to the dish actually shown.
  Future<FoodAnalysis> analyzeFoodByName(
    List<int> imageBytes,
    String name, {
    LocalFood? storedDish,
  }) async {
    final FoodAnalysisResponse response = await api.geminiLandmark
        .analyzeFoodWithName(
          imageBytes: imageBytes,
          name: name,
          storedDish: _storedDishPrompt(storedDish),
        );
    return (
      food: _toLocalFood(response),
      priceMin: response.priceMin,
      priceMax: response.priceMax,
      isLocal: response.isMalaysianLocalFood,
      confidence: response.confidence,
      localConfidence: response.localFoodConfidence,
      imageQuality: response.imageQuality,
      imageQualityIssues: response.imageQualityIssues,
      nameMatchesPhoto: response.nameMatchesPhoto,
      matchConfidence: response.matchConfidence,
      observedFood: response.observedFood.isNotEmpty
          ? response.observedFood
          : response.dish,
      foodType: response.foodType,
      dietaryRestrictions: response.dietaryRestrictions,
    );
  }

  /// Spelling check behind the manual-entry flow's typo gate: is
  /// [typedName] a MISSPELLING of the dish the photo showed
  /// ([observedFood])? Text-only - Gemini confirmed the photo matches the
  /// typed dish by the time this runs (see `FoodRecognitionLogic
  /// .resolveByName`). `isTypo` is only meaningful together with a non-empty
  /// `correctedName`; a verdict without a correction comes back as "no
  /// typo" (see `GeminiLandmarkService.checkTypedNameSpelling`).
  Future<({bool isTypo, String correctedName})> checkTypedNameSpelling({
    required String typedName,
    required String observedFood,
  }) => api.geminiLandmark.checkTypedNameSpelling(
    typedName: typedName,
    observedFood: observedFood,
  );

  /// 3-step origin verification for a dish name - the Option C gate before a
  /// genuinely-new food is written to `local_food` (see
  /// `FoodRecognitionLogic.registerNewDishes`). Three separately-framed
  /// Gemini questions each classify the dish into the a/b/c/d scheme
  /// (`OriginDishCase`); a check votes "Malaysian" for (a) origin, (b)
  /// adopted/naturalized or (d) shared regional. With no human-review queue,
  /// the split is resolved by rule: AT LEAST 2 of 3 must agree, otherwise the
  /// dish is rejected. Fail-closed: a check that errors counts as a "no"
  /// vote, so an unverifiable dish is never admitted on a broken call.
  Future<OriginVerification> verifyDishOrigin(String dishName) async {
    final Map<String, dynamic> direct = await _safeCheck(
      () => api.geminiLandmark.verifyOriginDirect(dishName),
    );
    final Map<String, dynamic> adjudicate = await _safeCheck(
      () => api.geminiLandmark.verifyOriginAdjudicate(dishName),
    );
    final Map<String, dynamic> knownPattern = await _safeCheck(
      () => api.geminiLandmark.verifyOriginKnownPattern(dishName),
    );

    final OriginDirectCheck c1 = (
      dishCase: OriginDishCase.fromLabel(direct['case']),
      originCountry: (direct['origin_country'] as String?)?.trim() ?? '',
      originEthnicity: (direct['origin_ethnicity'] as String?)?.trim() ?? '',
      confidence: ((direct['confidence'] as num?) ?? 0).toDouble(),
    );
    final OriginAdjudicateCheck c2 = (
      dishCase: OriginDishCase.fromLabel(adjudicate['case']),
      actualOriginCountry:
          (adjudicate['actual_origin_country'] as String?)?.trim() ?? '',
      distinguishingNotes:
          (adjudicate['distinguishing_notes'] as String?)?.trim() ?? '',
    );
    final OriginKnownPatternCheck c3 = (
      // Fail closed: a missing/broken check reads as "commonly misattributed"
      // (i.e. NOT a vote for Malaysian).
      isCommonlyMisattributed:
          (knownPattern['is_commonly_misattributed'] as bool?) ?? true,
      correctOriginIfMisattributed:
          (knownPattern['correct_origin_if_misattributed'] as String?)?.trim(),
      reasoning: (knownPattern['reasoning'] as String?)?.trim() ?? '',
    );

    // A check votes "Malaysian local food" when it classifies the dish as
    // (a) Malaysian origin, (b) adopted/naturalized or (d) shared regional.
    // At least 2 of 3 must agree - a single weak vote is not enough to create
    // a curated catalogue row.
    int votes = 0;
    if (c1.dishCase.isMalaysianLocalFood) votes++;
    if (c2.dishCase.isMalaysianLocalFood) votes++;
    if (!c3.isCommonlyMisattributed) votes++;

    return OriginVerification(
      dishName: dishName,
      verdict: votes >= 2 ? OriginVerdict.accept : OriginVerdict.reject,
      votesMalaysian: votes,
      directOrigin: c1,
      adjudicate: c2,
      knownPattern: c3,
    );
  }

  /// Runs one verification check, returning an empty map on any failure so a
  /// broken call never throws out of [verifyDishOrigin].
  Future<Map<String, dynamic>> _safeCheck(
    Future<Map<String, dynamic>> Function() check,
  ) async {
    try {
      return await check();
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// `FoodAnalysisResponse` (data model) -> `LocalFood` (domain model) - the
  /// only place this conversion lives. [name] overrides the dish field when
  /// the caller supplied its own name (the manual-entry path).
  LocalFood _toLocalFood(FoodAnalysisResponse response, {String? name}) =>
      LocalFood(
        id: 0, // Not yet saved - a repository assigns this once persisted.
        name: name ?? response.dish,
        description: response.description,
        ingredients: response.ingredients,
        origin: response.origin,
        culturalBackground: response.culturalBackground,
        category: response.foodCategory,
        cookingStyle: response.cookingStyle,
        mealType: response.mealType,
        foodType: _normaliseFoodType(response.foodType),
        tastes: response.tasteTags,
        mainTaste: response.mainTaste,
        pronunciationText: response.pronunciation,
        synonyms: response.variant.isEmpty
            ? const <String>[]
            : <String>[response.variant],
        aliases: response.aliases,
      );

  /// The curated row as the analysis prompts' STORED CATALOGUE RECORD (see
  /// [StoredDishPrompt]), or null when there is nothing stored to send - a
  /// brand-new dish carries `id == 0` and has no row yet.
  static StoredDishPrompt? _storedDishPrompt(LocalFood? food) {
    if (food == null || food.id == 0) return null;
    return (
      name: food.name,
      category: food.category,
      description: food.description,
      ingredients: food.ingredients,
      culturalBackground: food.culturalBackground,
    );
  }

  /// Gemini's dish-type classification -> a valid catalogue `food_type`
  /// value (proper case). Unknown / "none" / blank falls back to "Food" so a
  /// validly-addable dish always carries a canonical type on `LocalFood`;
  /// the raw classification is still carried on `FoodAnalysis.foodType` for
  /// the addability gate.
  static String _normaliseFoodType(String raw) {
    final String t = raw.trim().toLowerCase();
    for (final String value in const <String>[
      'Food',
      'Beverage',
      'Fruit',
      'Dessert',
      'Kuih',
    ]) {
      if (value.toLowerCase() == t) return value;
    }
    return 'Food';
  }

  /// Restaurant signboard photo - extracts the name (UC500, A7/A19).
  Future<SignboardAnalysisResponse> analyzeSignboard(List<int> imageBytes) =>
      api.geminiLandmark.analyzeSignboardImage(imageBytes: imageBytes);

  /// Stall photo - frame validation only, no auto-fill (UC500, A8/A15).
  Future<StallAnalysisResponse> analyzeStall(List<int> imageBytes) =>
      api.geminiLandmark.analyzeStallImage(imageBytes: imageBytes);

  /// The SIGNBOARD photo asked a second question (UC500): the form is
  /// holding a name the tourist EDITED, so how well does [typedName] match
  /// the name painted on the signboard? See
  /// `LandmarkSubmissionLogic.nameMatchesSignboard`.
  Future<SignboardNameMatchResponse> verifySignboardName({
    required List<int> imageBytes,
    required String typedName,
  }) => api.geminiLandmark.verifySignboardName(
    imageBytes: imageBytes,
    typedName: typedName,
  );

  /// Two photos, one question (UC500): the tourist's own capture against the
  /// stored photo of a NEARBY place whose name looks like theirs - do they
  /// show the same restaurant? See
  /// `LandmarkSubmissionLogic.photosShowSamePlace`.
  Future<PlacePhotoMatchResponse> comparePlacePhotos({
    required List<int> imageBytes,
    required List<int> otherImageBytes,
  }) => api.geminiLandmark.comparePlacePhotos(
    imageBytes: imageBytes,
    otherImageBytes: otherImageBytes,
  );
}
