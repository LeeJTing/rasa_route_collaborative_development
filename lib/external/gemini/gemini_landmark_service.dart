import 'dart:convert';

import '../../app/config/env.dart';
import '../../model/data_models/food_analysis_response.dart';
import '../../model/data_models/signboard_analysis_response.dart';
import '../../model/data_models/stall_analysis_response.dart';
import 'gemini_service.dart';

/// UC500's food/signboard/stall recognition prompts, sent through the
/// generic `GeminiService` rather than each feature owning its own copy of
/// the HTTP/JSON-parsing plumbing. `GeminiService` itself has no
/// feature-specific prompts anymore - those used to live there, but were
/// pulled out into this dedicated service so `GeminiService` stays reusable
/// by whatever other features need Gemini for their own purposes.
///
/// Uses its own API key (`Env.geminiApiKeyLandmark`, falling back to the
/// shared `Env.geminiApiKey` if unset) - passed explicitly to `GeminiService`
/// on every call - so this feature's usage/quota can be tracked separately
/// from whatever else calls `GeminiService` directly.
///
/// Reached only through `APIManager` (`api.geminiLandmark`). A singleton,
/// like every other shared client.
class GeminiLandmarkService {
  factory GeminiLandmarkService() => _instance;

  GeminiLandmarkService._();

  static final GeminiLandmarkService _instance = GeminiLandmarkService._();

  final GeminiService _gemini = GeminiService();

  /// Toggle for the real Gemini calls. `true` (default) sends requests to
  /// Gemini and parses its JSON replies; `false` returns canned stub data
  /// and makes NO HTTP calls.
  static final bool useLiveGemini = true;

  /// Strips a surrounding ```json fence if present, then parses the JSON
  /// body into a map. Gemini sometimes wraps its JSON reply in a markdown
  /// code fence; this keeps the raw-HTTP/plumbing concerns in
  /// `GeminiService` while owning the (feature-local) response parsing here.
  Map<String, dynamic> _decodeJsonObject(String raw) {
    final String trimmed = raw.trim();
    final RegExp fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final Match? fenceMatch = fence.firstMatch(trimmed);
    final String body = fenceMatch?.group(1) ?? trimmed;
    final dynamic decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw FormatException('Gemini returned non-object JSON: $body');
  }

  /// Coerces a Gemini JSON price into a `double`. Gemini may return the
  /// suggested range as a JSON number, OR as a string (e.g. `"2.00"` or
  /// `"RM 2.00"`) - `as num?` would silently drop string values and the
  /// range would never reach `landmark_item.price_min`/`price_max`. Returns
  /// `0` when the field is absent/blank, matching `FoodAnalysisResponse`'s
  /// "0 means unknown" convention.
  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final String cleaned = value.trim().replaceAll(RegExp(r'[^0-9.]'), '');
      return double.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  /// Quick, name-only call - phase 1 of the two-phase recognition flow.
  /// Cheaper than [analyzeFoodImage]: only `dish` and the status fields are
  /// meaningful on the response. Used to check the catalogue first; the full
  /// call only happens if the dish isn't already there (see
  /// `FoodRecognitionLogic.recognizeFood`).
  /// Errors: A2 (timeout), A3 (not local food), A4 (no food), A18 (incomplete)
  Future<FoodAnalysisResponse> identifyFoodName({
    required List<int> imageBytes,
  }) async {
    if (useLiveGemini) return _identifyFoodNameLive(imageBytes);

    // Stub fallback - only reached while the live call is disabled.
    return const FoodAnalysisResponse(
      dish: 'Nasi Lemak',
      variant: '',
      description: '',
      origin: '',
      cookingStyle: '',
      mealType: '',
      foodCategory: '',
      isMalaysianLocalFood: true,
      culturalBackground: '',
      foodStatus: 'detected',
      foodImageStatus: 'complete',
      confidence: 0.9,
      foodCount: 1,
      candidates: <FoodCandidate>[
        FoodCandidate(dish: 'Nasi Lemak', confidence: 0.9),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live Gemini implementations - real API calls, gated behind [useLiveGemini]
  // by the public dispatch methods above.
  // ---------------------------------------------------------------------------

  Future<FoodAnalysisResponse> _identifyFoodNameLive(
    List<int> imageBytes,
  ) async {
    const String prompt = '''
  Look at this food image and report:

  1. foodCount: how many SEPARATE, distinct food items/dishes are clearly
     visible? A single dish/plate/portion counts as one. Count distinct
     dishes, not every piece of food on one plate.

  2. dish: the MAIN dish name (when only one food is present). If you are
     not sure, give your best guess but set confidence low - NEVER invent a
     plausible-sounding dish for an unidentifiable photo.

  3. candidates: list up to 3 POSSIBLE dish names for the main food, most
     likely first, each with a confidence 0.0-1.0. If you are confident it
     is one dish, list only that one with a high confidence.

  4. Is this a Malaysian local food? (true/false). Malaysian STREET food and
     hawker adaptations count as local even if the base dish sounds
     international - e.g. Ramly burger, nasi campur, pisang goreng, cendol,
     roti john, keropok lekor.

  5. Food detection status: "detected" | "not_detected" | "unclear"
     - use "unclear" when food is visible but you cannot confidently name it
     - never claim "detected" with a made-up dish

  6. Frame status: is the ENTIRE food visible within the frame?
     - "complete" if fully visible
     - "partially_captured" if cut off/partially outside frame
     - "obstructed" if blocked/unclear

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "foodCount": 1,
    "dish": "string",
    "candidates": [{"dish": "string", "confidence": 0.0-1.0}],
    "isMalaysianLocalFood": boolean,
    "foodStatus": "detected|not_detected|unclear",
    "foodImageStatus": "complete|partially_captured|obstructed",
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return FoodAnalysisResponse(
      dish: (json['dish'] as String?) ?? '',
      variant: '',
      description: '',
      origin: '',
      cookingStyle: '',
      mealType: '',
      foodCategory: '',
      isMalaysianLocalFood: (json['isMalaysianLocalFood'] as bool?) ?? false,
      culturalBackground: '',
      foodStatus: (json['foodStatus'] as String?) ?? 'unclear',
      foodImageStatus: (json['foodImageStatus'] as String?) ?? 'unclear',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      foodCount: (json['foodCount'] as num?)?.toInt() ?? 1,
      candidates: <FoodCandidate>[
        for (final dynamic c
            in json['candidates'] as List<dynamic>? ?? const <dynamic>[])
          if (c is Map<String, dynamic>) FoodCandidate.fromJson(c),
      ],
    );
  }

  /// Full call - phase 2, only reached when the dish from [identifyFoodName]
  /// isn't already in the catalogue (REQ106_2, REQ106_7).
  /// Returns: dish, variant, origin, category, meal type, frame status, etc.
  /// Errors: A2 (timeout), A3 (not local food), A4 (no food), A18 (incomplete)
  Future<FoodAnalysisResponse> analyzeFoodImage({
    required List<int> imageBytes,
  }) async {
    if (useLiveGemini) return _analyzeFoodImageLive(imageBytes);

    // Stub fallback - only reached while the live call is disabled.
    return const FoodAnalysisResponse(
      dish: 'Nasi Lemak',
      variant: 'Nasi Lemak Biasa',
      description:
          'Coconut rice with sambal, peanuts, anchovies and boiled egg.',
      origin: 'Melaka & Negeri Sembilan',
      cookingStyle: 'Simmering',
      mealType: 'Breakfast',
      foodCategory: 'Malay',
      isMalaysianLocalFood: true,
      culturalBackground: 'Traditional breakfast dish of the Malay Peninsula.',
      tasteTags: <String>['Spicy', 'Sweet', 'Rich'],
      foodStatus: 'detected',
      foodImageStatus: 'complete',
      confidence: 0.95,
      priceMin: 2.0,
      priceMax: 8.0,
      foodCount: 1,
    );
  }

  Future<FoodAnalysisResponse> _analyzeFoodImageLive(
    List<int> imageBytes,
  ) async {
    const String prompt = '''
  Analyze this food image and extract the following information:

  1. Identify the dish name
  2. Identify the dish variant
  3. Provide a brief description
  4. Identify the origin/region
  5. Identify the cooking style
  6. Identify the meal type (Breakfast/Lunch/Dinner/Snack)
  7. Categorize: Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other
  8. Is this a Malaysian local food? (true/false). Malaysian STREET food and
     hawker adaptations count as local even if the base dish sounds
     international - e.g. Ramly burger, nasi campur, roti john, cendol.
  9. Cultural background
  10. Taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3

  11. Frame status: Is the ENTIRE food visible within the frame?
      - "complete" if fully visible
      - "partially_captured" if cut off/partially outside frame
      - "obstructed" if blocked/unclear

  12. Food detection status:
      - "detected" if food is clearly visible
      - "not_detected" if no food found
      - "unclear" if ambiguous

  13. Suggested selling price range for this dish in MYR (a typical stall /
      restaurant price): "suggestedPriceMin" and "suggestedPriceMax".

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "dish": "string",
    "variant": "string",
    "description": "string",
    "origin": "string",
    "cookingStyle": "string",
    "mealType": "string",
    "foodCategory": "string",
    "isMalaysianLocalFood": boolean,
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "foodStatus": "detected|not_detected|unclear",
    "foodImageStatus": "complete|partially_captured|obstructed",
    "suggestedPriceMin": 0.0,
    "suggestedPriceMax": 0.0,
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return FoodAnalysisResponse(
      dish: (json['dish'] as String?) ?? '',
      variant: (json['variant'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      origin: (json['origin'] as String?) ?? '',
      cookingStyle: (json['cookingStyle'] as String?) ?? '',
      mealType: (json['mealType'] as String?) ?? '',
      foodCategory: (json['foodCategory'] as String?) ?? '',
      isMalaysianLocalFood: (json['isMalaysianLocalFood'] as bool?) ?? false,
      culturalBackground: (json['culturalBackground'] as String?) ?? '',
      tasteTags:
          (json['tasteTags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      foodStatus: (json['foodStatus'] as String?) ?? 'unclear',
      foodImageStatus: (json['foodImageStatus'] as String?) ?? 'unclear',
      priceMin: _asDouble(json['suggestedPriceMin']),
      priceMax: _asDouble(json['suggestedPriceMax']),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      foodCount: (json['foodCount'] as num?)?.toInt() ?? 1,
    );
  }

  /// Full call with the tourist's typed dish name - the manual "type the food
  /// name" fallback (see `FoodRecognitionLogic.resolveByName`). The user's
  /// [name] is sent ALONGSIDE the image so Gemini verifies the photo against
  /// that name (confidence) and returns the details for exactly that one dish
  /// - never a candidate list, always the single dish the user named.
  /// Errors: A2 (timeout)
  Future<FoodAnalysisResponse> analyzeFoodWithName({
    required List<int> imageBytes,
    required String name,
  }) async {
    if (useLiveGemini) return _analyzeFoodWithNameLive(imageBytes, name);

    // Stub fallback - only reached while the live call is disabled.
    return FoodAnalysisResponse(
      dish: name,
      variant: '',
      description: 'Details for $name.',
      origin: '',
      cookingStyle: '',
      mealType: '',
      foodCategory: '',
      isMalaysianLocalFood: true,
      culturalBackground: '',
      tasteTags: const <String>[],
      foodStatus: 'detected',
      foodImageStatus: 'complete',
      confidence: 0.9,
      foodCount: 1,
    );
  }

  Future<FoodAnalysisResponse> _analyzeFoodWithNameLive(
    List<int> imageBytes,
    String name,
  ) async {
    final String prompt =
        '''
  The user has told us the dish in this photo is called "$name".

  Analyze the image and:
  1. Confirm whether the photo plausibly shows "$name" - report a confidence
     score 0.0-1.0.
  2. Provide the details for "$name" (the dish the user named), not any other
     food that might also be visible:
     - variant
     - a brief description
     - origin/region
     - cooking style
     - meal type (Breakfast/Lunch/Dinner/Snack)
     - food category (Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other)
     - isMalaysianLocalFood (true/false)
     - cultural background
     - taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3
     - a suggested selling price range in MYR (suggestedPriceMin and
       suggestedPriceMax)

  Return ONLY raw JSON for "$name", no markdown fences, no candidate list:
  {
    "dish": "$name",
    "variant": "string",
    "description": "string",
    "origin": "string",
    "cookingStyle": "string",
    "mealType": "string",
    "foodCategory": "string",
    "isMalaysianLocalFood": boolean,
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "foodStatus": "detected|not_detected|unclear",
    "foodImageStatus": "complete|partially_captured|obstructed",
    "suggestedPriceMin": 0.0,
    "suggestedPriceMax": 0.0,
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return FoodAnalysisResponse(
      dish: name,
      variant: (json['variant'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      origin: (json['origin'] as String?) ?? '',
      cookingStyle: (json['cookingStyle'] as String?) ?? '',
      mealType: (json['mealType'] as String?) ?? '',
      foodCategory: (json['foodCategory'] as String?) ?? '',
      isMalaysianLocalFood: (json['isMalaysianLocalFood'] as bool?) ?? false,
      culturalBackground: (json['culturalBackground'] as String?) ?? '',
      tasteTags:
          (json['tasteTags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      foodStatus: (json['foodStatus'] as String?) ?? 'unclear',
      foodImageStatus: (json['foodImageStatus'] as String?) ?? 'unclear',
      priceMin: _asDouble(json['suggestedPriceMin']),
      priceMax: _asDouble(json['suggestedPriceMax']),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      foodCount: 1,
    );
  }

  /// Analyze signboard image to extract restaurant name (REQ106_31, REQ106_37)
  /// Returns: extracted text + frame status
  /// Errors: A2 (timeout), A7 (no text), A19 (incomplete frame)
  Future<SignboardAnalysisResponse> analyzeSignboardImage({
    required List<int> imageBytes,
  }) async {
    if (useLiveGemini) return _analyzeSignboardImageLive(imageBytes);

    // Stub fallback - only reached while the live call is disabled.
    return const SignboardAnalysisResponse(
      signboardStatus: 'detected',
      textDetected: 'Village Park Restaurant',
      signboardImageStatus: 'complete',
      confidence: 0.9,
    );
  }

  Future<SignboardAnalysisResponse> _analyzeSignboardImageLive(
    List<int> imageBytes,
  ) async {
    const String prompt = '''
  Analyze this restaurant/stall signboard photo.

  The "frame" means the four edges of the image itself. A signboard is ONLY
  "fully in frame" when its ENTIRE outline - all four corners and edges -
  sits fully inside the image with clear margin and is not cut off anywhere.

  Check the signboard against ALL four image edges (top, bottom, left,
  right):
  - "complete": the whole signboard is fully visible, no corner or edge
    touches or crosses the image border, nothing is clipped.
  - "partially_captured": ANY part of the signboard touches or crosses any
    image edge, OR any corner/edge is clipped/cut off - even if the name is
    still readable.
  - "obstructed": part of the signboard is hidden behind something else.

  Steps:
  1. Locate the signboard and check its position against the four edges.
  2. Is this a valid restaurant/stall signboard? (yes/no)
  3. Extract ALL visible text (restaurant name, slogan, etc.).

  IMPORTANT: the name being readable does NOT mean the signboard is fully in
  frame. Judge completeness ONLY by whether any part of the signboard is
  clipped at the image edges.

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "signboardStatus": "detected|not_detected|unclear",
    "textDetected": "Extracted text or null",
    "signboardImageStatus": "complete|partially_captured|obstructed",
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return SignboardAnalysisResponse(
      signboardStatus: (json['signboardStatus'] as String?) ?? 'unclear',
      textDetected: json['textDetected'] as String?,
      signboardImageStatus:
          (json['signboardImageStatus'] as String?) ?? 'unclear',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
    );
  }

  /// Analyze stall image to verify stall detection and frame completeness (UC500)
  /// Returns: stall detection status + frame status (NO auto-fill)
  /// Errors: A2 (timeout), A8 (not detected), A15 (incomplete frame)
  Future<StallAnalysisResponse> analyzeStallImage({
    required List<int> imageBytes,
  }) async {
    if (useLiveGemini) return _analyzeStallImageLive(imageBytes);

    // Stub fallback - only reached while the live call is disabled.
    return const StallAnalysisResponse(
      stallStatus: 'detected',
      stallImageStatus: 'complete',
      confidence: 0.85,
    );
  }

  Future<StallAnalysisResponse> _analyzeStallImageLive(
    List<int> imageBytes,
  ) async {
    const String prompt = '''
  Analyze this food stall image:

  1. Is this a food stall/food shop? (yes/no)
  2. Is the ENTIRE stall visible within the frame?
      - "complete" if fully visible
      - "partially_captured" if cut off/partially outside frame
      - "obstructed" if blocked/unclear

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "stallStatus": "detected|not_detected|unclear",
    "stallImageStatus": "complete|partially_captured|obstructed",
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      model: Env.geminiModelLandmark,
      apiKey: Env.geminiApiKeyLandmark,
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return StallAnalysisResponse(
      stallStatus: (json['stallStatus'] as String?) ?? 'unclear',
      stallImageStatus: (json['stallImageStatus'] as String?) ?? 'unclear',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
    );
  }
}
