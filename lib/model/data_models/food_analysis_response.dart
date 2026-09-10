import '../../core/json_model.dart';

/// Response from Gemini food image analysis.
///
/// Wire format: what Gemini API returns after analyzing a food image.
/// Converted to `LocalFood` domain model by the repository.
class FoodAnalysisResponse implements JsonModel {
  const FoodAnalysisResponse({
    required this.dish,
    required this.variant,
    required this.description,
    required this.origin,
    required this.cookingStyle,
    required this.mealType,
    required this.foodCategory,
    this.foodType = '',
    required this.isMalaysianLocalFood,
    required this.culturalBackground,
    required this.foodStatus,
    required this.foodImageStatus,
    this.confidence = 1.0,
    this.localFoodConfidence = 1.0,
    this.localFoodReasoning = '',
    this.imageQuality = 'good',
    this.imageQualityIssues = const <String>[],
    this.tasteTags = const <String>[],
    this.mainTaste = '',
    this.dietaryRestrictions = const <String>[],
    this.aliases = const <String>[],
    this.foodCount = 1,
    this.candidates = const <FoodCandidate>[],
    this.priceMin = 0,
    this.priceMax = 0,
    this.nameMatchesPhoto = true,
    this.matchConfidence = 0,
    this.observedFood = '',
    this.ingredients = '',
  });

  /// Dish name (e.g., "Nasi Lemak")
  final String dish;

  /// Dish variant (e.g., "Nasi Lemak Biasa", "Nasi Lemak Sambal Kencur")
  final String variant;

  /// Dish description
  final String description;

  /// Main ingredients, comma-separated (e.g. "rice, coconut milk, sambal,
  /// peanuts, anchovies, egg"). Empty when Gemini didn't supply them.
  final String ingredients;

  /// Origin/region (e.g., "Melaka & Negeri Sembilan")
  final String origin;

  /// Cooking style (e.g., "Simmering", "Frying")
  final String cookingStyle;

  /// Meal type (e.g., "Breakfast", "Lunch", "Dinner")
  final String mealType;

  /// Food category (e.g., "Malay", "Chinese", "Indian", "Nyonya", "Sabah", "Sarawak")
  final String foodCategory;

  /// The app's catalogue dish type: "Food" | "Beverage" | "Fruit" | "Dessert"
  /// | "Kuih" - or "none" (or empty) when the item is NOT an addable dish
  /// type (a snack, packaged item, canned/bottled drink, confectionery...).
  /// Drives the "Malaysian product but can't be added" gate in
  /// `FoodRecognitionLogic` (see `FoodRecognitionResult.fitsCatalogueCategory`).
  final String foodType;

  /// Is this a Malaysian local food? (REQ106_10)
  final bool isMalaysianLocalFood;

  /// Cultural background
  final String culturalBackground;

  /// Detection status: "detected" | "not_detected" | "unclear"
  /// Used for error handling (A3, A4, A18)
  final String foodStatus;

  /// Frame completeness: "complete" | "partially_captured" | "obstructed"
  /// Used for error handling (A18)
  final String foodImageStatus;

  /// Confidence score 0.0 - 1.0
  final double confidence;

  /// How sure Gemini is about the [isMalaysianLocalFood] judgement
  /// SPECIFICALLY - separate from [confidence], which is about naming the
  /// dish. The two genuinely differ: a photo can be an unmistakable burger
  /// (high [confidence]) while whether it's a Malaysian Ramly-style burger
  /// or a Western chain burger is a much closer call (low
  /// [localFoodConfidence]). Folding them into one number hid exactly the
  /// uncertainty that matters for the "can this become a landmark" gate.
  final double localFoodConfidence;

  /// One short sentence naming the dish's origin and which class Gemini put
  /// it in. Forcing the model to state its reasoning BEFORE the boolean
  /// measurably improves the boolean - and it gives a human something to
  /// check when a judgement looks wrong. Not shown in the UI; useful in
  /// logs/debugging.
  final String localFoodReasoning;

  /// Whether the photo plausibly shows the dish the tourist typed by hand
  /// (only `GeminiLandmarkService.analyzeFoodWithName` verifies a typed
  /// name). `true` for every other call. When `false`, [dish] is what the
  /// photo ACTUALLY shows, not what was typed.
  final bool nameMatchesPhoto;

  /// How sure (0..1) Gemini is of [nameMatchesPhoto] specifically. `0` when
  /// not applicable (non-verification calls).
  final double matchConfidence;

  /// What Gemini sees in the photo, in its own words, BEFORE considering the
  /// typed name - used by the UI to say "this photo looks more like X".
  /// Empty for non-verification calls.
  final String observedFood;

  /// Overall usability of the PHOTO itself (not the food):
  /// "good" | "acceptable" | "poor". "poor" means blur, bad exposure or a
  /// strong colour cast is bad enough to make identification unreliable.
  final String imageQuality;

  /// The specific problems behind a non-"good" [imageQuality] - e.g.
  /// `["blurry", "too_dark"]`. Empty when the photo is fine.
  final List<String> imageQualityIssues;

  /// Flavour tags (e.g. "Spicy", "Sweet", "Rich"). Only populated by the
  /// full analysis call, not the quick name-only one - left empty there.
  final List<String> tasteTags;

  /// The single primary taste from [tasteTags] - it marks `is_main` on the
  /// `local_food_preference` link when a new food is written to the
  /// catalogue (mirrors the scraper's `main_taste`). Empty when unknown.
  final String mainTaste;

  /// Dietary restrictions that apply to this dish, using the canonical
  /// `dietary_restriction.restriction_name` strings (e.g. "No Pork",
  /// "No Beef", "Vegetarian"). Only populated by the full analysis calls;
  /// empty when none apply.
  final List<String> dietaryRestrictions;

  /// Well-known alternative names for the identified dish - other
  /// languages/scripts/spellings of the SAME dish (e.g. "摩摩喳喳" for
  /// Bubur Cha Cha, "ABC" for ais kacang). Populated by the full analysis
  /// calls; empty when none are known. Used ONLY to match the dish against
  /// the curated catalogue (never written to `local_food`).
  final List<String> aliases;

  /// How many SEPARATE, distinct food items/dishes are clearly visible in the
  /// image. A single dish/plate/portion counts as one. > 1 means the tourist
  /// should re-capture with only one food in frame. Only populated by the
  /// quick name-only call (defaults to 1 elsewhere).
  final int foodCount;

  /// Up to 3 possible dish names for the food, most-likely first, each with a
  /// 0..1 confidence. When [foodCount] == 1 and there are >= 2 high-confidence
  /// candidates, the app shows these as a top-3 picker (A5). Only populated by
  /// the quick name-only call (defaults to empty elsewhere).
  final List<FoodCandidate> candidates;

  /// Suggested selling price range for the dish, in MYR (Gemini's estimate -
  /// used to warn the tourist if they type a price that looks like a typo).
  /// `0` means Gemini didn't supply one (unknown). Only populated by the
  /// full analysis calls.
  final double priceMin;
  final double priceMax;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'dish': dish,
    'variant': variant,
    'description': description,
    'ingredients': ingredients,
    'origin': origin,
    'cookingStyle': cookingStyle,
    'mealType': mealType,
    'foodCategory': foodCategory,
    'foodType': foodType,
    'isMalaysianLocalFood': isMalaysianLocalFood,
    'culturalBackground': culturalBackground,
    'foodStatus': foodStatus,
    'foodImageStatus': foodImageStatus,
    'confidence': confidence,
    'localFoodConfidence': localFoodConfidence,
    'localFoodReasoning': localFoodReasoning,
    'nameMatchesPhoto': nameMatchesPhoto,
    'matchConfidence': matchConfidence,
    'observedFood': observedFood,
    'imageQuality': imageQuality,
    'imageQualityIssues': imageQualityIssues,
    'tasteTags': tasteTags,
    'mainTaste': mainTaste,
    'dietaryRestrictions': dietaryRestrictions,
    'aliases': aliases,
    'foodCount': foodCount,
    'candidates': candidates.map((FoodCandidate c) => c.toJson()).toList(),
    'priceMin': priceMin,
    'priceMax': priceMax,
  };

  FoodAnalysisResponse copyWith({
    String? dish,
    String? variant,
    String? description,
    String? ingredients,
    String? origin,
    String? cookingStyle,
    String? mealType,
    String? foodCategory,
    String? foodType,
    bool? isMalaysianLocalFood,
    String? culturalBackground,
    String? foodStatus,
    String? foodImageStatus,
    double? confidence,
    double? localFoodConfidence,
    String? localFoodReasoning,
    bool? nameMatchesPhoto,
    double? matchConfidence,
    String? observedFood,
    String? imageQuality,
    List<String>? imageQualityIssues,
    List<String>? tasteTags,
    String? mainTaste,
    List<String>? dietaryRestrictions,
    List<String>? aliases,
    int? foodCount,
    List<FoodCandidate>? candidates,
    double? priceMin,
    double? priceMax,
  }) => FoodAnalysisResponse(
    dish: dish ?? this.dish,
    variant: variant ?? this.variant,
    description: description ?? this.description,
    ingredients: ingredients ?? this.ingredients,
    origin: origin ?? this.origin,
    cookingStyle: cookingStyle ?? this.cookingStyle,
    mealType: mealType ?? this.mealType,
    foodCategory: foodCategory ?? this.foodCategory,
    foodType: foodType ?? this.foodType,
    isMalaysianLocalFood: isMalaysianLocalFood ?? this.isMalaysianLocalFood,
    culturalBackground: culturalBackground ?? this.culturalBackground,
    foodStatus: foodStatus ?? this.foodStatus,
    foodImageStatus: foodImageStatus ?? this.foodImageStatus,
    confidence: confidence ?? this.confidence,
    localFoodConfidence: localFoodConfidence ?? this.localFoodConfidence,
    localFoodReasoning: localFoodReasoning ?? this.localFoodReasoning,
    nameMatchesPhoto: nameMatchesPhoto ?? this.nameMatchesPhoto,
    matchConfidence: matchConfidence ?? this.matchConfidence,
    observedFood: observedFood ?? this.observedFood,
    imageQuality: imageQuality ?? this.imageQuality,
    imageQualityIssues: imageQualityIssues ?? this.imageQualityIssues,
    tasteTags: tasteTags ?? this.tasteTags,
    mainTaste: mainTaste ?? this.mainTaste,
    dietaryRestrictions: dietaryRestrictions ?? this.dietaryRestrictions,
    aliases: aliases ?? this.aliases,
    foodCount: foodCount ?? this.foodCount,
    candidates: candidates ?? this.candidates,
    priceMin: priceMin ?? this.priceMin,
    priceMax: priceMax ?? this.priceMax,
  );
}

/// One candidate dish name (and its confidence) from the quick recognition
/// call - used for the top-3 picker (A5) when Gemini is uncertain which of a
/// few likely dishes the photo shows.
class FoodCandidate {
  const FoodCandidate({required this.dish, required this.confidence});

  factory FoodCandidate.fromJson(Map<String, dynamic> json) => FoodCandidate(
    dish: (json['dish'] as String?) ?? '',
    confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
  );

  final String dish;

  /// 0..1
  final double confidence;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'dish': dish,
    'confidence': confidence,
  };
}
