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
    required this.isMalaysianLocalFood,
    required this.culturalBackground,
    required this.foodStatus,
    required this.foodImageStatus,
    this.confidence = 1.0,
    this.tasteTags = const <String>[],
    this.foodCount = 1,
    this.candidates = const <FoodCandidate>[],
    this.priceMin = 0,
    this.priceMax = 0,
  });

  /// Dish name (e.g., "Nasi Lemak")
  final String dish;

  /// Dish variant (e.g., "Nasi Lemak Biasa", "Nasi Lemak Sambal Kencur")
  final String variant;

  /// Dish description
  final String description;

  /// Origin/region (e.g., "Melaka & Negeri Sembilan")
  final String origin;

  /// Cooking style (e.g., "Simmering", "Frying")
  final String cookingStyle;

  /// Meal type (e.g., "Breakfast", "Lunch", "Dinner")
  final String mealType;

  /// Food category (e.g., "Malay", "Chinese", "Indian", "Nyonya", "Sabah", "Sarawak")
  final String foodCategory;

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

  /// Flavour tags (e.g. "Spicy", "Sweet", "Rich"). Only populated by the
  /// full analysis call, not the quick name-only one - left empty there.
  final List<String> tasteTags;

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
    'origin': origin,
    'cookingStyle': cookingStyle,
    'mealType': mealType,
    'foodCategory': foodCategory,
    'isMalaysianLocalFood': isMalaysianLocalFood,
    'culturalBackground': culturalBackground,
    'foodStatus': foodStatus,
    'foodImageStatus': foodImageStatus,
    'confidence': confidence,
    'tasteTags': tasteTags,
    'foodCount': foodCount,
    'candidates': candidates.map((FoodCandidate c) => c.toJson()).toList(),
    'priceMin': priceMin,
    'priceMax': priceMax,
  };

  FoodAnalysisResponse copyWith({
    String? dish,
    String? variant,
    String? description,
    String? origin,
    String? cookingStyle,
    String? mealType,
    String? foodCategory,
    bool? isMalaysianLocalFood,
    String? culturalBackground,
    String? foodStatus,
    String? foodImageStatus,
    double? confidence,
    List<String>? tasteTags,
    int? foodCount,
    List<FoodCandidate>? candidates,
    double? priceMin,
    double? priceMax,
  }) => FoodAnalysisResponse(
    dish: dish ?? this.dish,
    variant: variant ?? this.variant,
    description: description ?? this.description,
    origin: origin ?? this.origin,
    cookingStyle: cookingStyle ?? this.cookingStyle,
    mealType: mealType ?? this.mealType,
    foodCategory: foodCategory ?? this.foodCategory,
    isMalaysianLocalFood: isMalaysianLocalFood ?? this.isMalaysianLocalFood,
    culturalBackground: culturalBackground ?? this.culturalBackground,
    foodStatus: foodStatus ?? this.foodStatus,
    foodImageStatus: foodImageStatus ?? this.foodImageStatus,
    confidence: confidence ?? this.confidence,
    tasteTags: tasteTags ?? this.tasteTags,
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
