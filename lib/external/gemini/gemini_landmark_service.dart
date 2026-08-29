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

  /// Shared prompt block defining how to judge "is this Malaysian local
  /// food". Written as an explicit DECISION PROCEDURE rather than a bare
  /// question, because the bare question proved unreliable in testing:
  ///  - it gave no criteria, so the model invented its own standard per call;
  ///  - it never addressed the central confusion ("sold in Malaysia" is NOT
  ///    the same as "Malaysian food"), so anything photographed in Malaysia
  ///    tended to pass;
  ///  - it listed only POSITIVE examples, biasing borderline cases to true;
  ///  - it asked for the boolean directly, with no reasoning step - models
  ///    are markedly more accurate when made to name the dish's origin
  ///    first, then classify;
  ///  - it reused the single `confidence` field, so an obvious dish with a
  ///    genuinely borderline local-ness call still looked fully certain.
  ///
  /// Kept in one constant so every call judges by exactly the same rules -
  /// previously each prompt had its own looser wording.
  static const String _localFoodRules = '''
  MALAYSIAN LOCAL FOOD - follow this procedure, do not shortcut it:

  Step 1. Name the dish as specifically as the photo allows.
  Step 2. Ask where THAT DISH originated or became established as everyday
          food. Judge the DISH, never the location of the photo - a dish is
          not Malaysian merely because it is sold in Malaysia.
  Step 2b. Use visible CONTEXT as evidence for WHICH dish it is:
    - branded packaging, wrappers, cups, trays, logos
    - the stall/kitchen behind the food, banana-leaf or newspaper wrapping,
      typical hawker plating
    A branded Western chain wrapper is strong evidence for class (c).
    Roadside-stall wrapping, a mamak/kopitiam setting or banana-leaf serving
    is evidence for class (a).

    CAVEAT: this evidence identifies the DISH, it does not decide origin by
    itself. Malaysian surroundings do NOT make a foreign dish Malaysian - a
    chain burger eaten at a Malaysian mall is still class (c).
  Step 3. Put it in exactly ONE class:
    (a) MALAYSIAN - originated in Malaysia, OR is a Malaysian hawker/street
        adaptation Malaysians eat as everyday local food.
        e.g. nasi lemak, char kway teow, roti canai, satay, asam laksa,
        cendol, Ramly burger, roti john, nasi campur, pisang goreng,
        keropok lekor, apam balik, teh tarik, bak kut teh, mee goreng mamak,
        nasi kandar, murtabak, rendang, kaya toast, curry mee, ais kacang.
    (b) SHARED REGIONAL - eaten across Malaysia/Singapore/Indonesia/Brunei
        and genuinely part of Malaysian everyday food culture.
        e.g. nasi goreng, mee rebus, soto ayam, lontong, rojak, popiah.
    (c) FOREIGN - a foreign dish sold in Malaysia with no distinct Malaysian
        identity of its own.
        e.g. sushi, ramen, pho, pad thai, pizza, spaghetti, croissant,
        a burger or fried chicken from a Western fast-food chain,
        Korean fried chicken, plain Western steak, doughnuts.
    (d) UNIDENTIFIABLE - you genuinely cannot tell what the dish is.

  Step 4. Report all three of these:
    - "localFoodReasoning": ONE short sentence - the dish, its origin, and
      the class letter you chose. e.g. "Ramly burger - Malaysian street
      adaptation sold at roadside stalls, class (a)."
    - "isMalaysianLocalFood": true for (a) and (b); false for (c) and (d).
    - "localFoodConfidence": 0.0-1.0 - how sure you are of THIS judgement
      specifically. This is SEPARATE from "confidence" (how sure you are of
      the dish NAME). A clearly-photographed burger may score high
      "confidence" but low "localFoodConfidence" if you cannot tell whether
      it is a Ramly-style or a Western-chain burger.

  CRITICAL: being sold in Malaysia does NOT make a dish Malaysian. A burger
  from a Western chain is class (c); a Ramly burger is class (a). If you
  cannot distinguish which the photo shows, say so with a LOW
  "localFoodConfidence" rather than guessing true.

  CONFIDENCE CALIBRATION - use the full range, do not default to high:
    0.90-1.00  Certain. The dish is unmistakable and clearly photographed.
    0.70-0.89  Confident, but a similar dish could be confused with it.
    0.50-0.69  Plausible best guess; you would not be surprised to be wrong.
    0.30-0.49  Weak guess - several dishes fit equally well.
    0.00-0.29  You genuinely cannot tell.

  If you would not bet on your answer, score below 0.6. An honest low score
  is far more useful to us than a confident wrong one - a low score makes
  the app ask the user to confirm, which is the correct outcome.
  ''';

  /// Shared prompt block for judging the PHOTO's own usability. Added
  /// because nothing previously asked about it at all - a dark, blurry,
  /// colour-cast photo could still come back with `confidence: 0.9`, since
  /// the model was only ever asked about the food, never the image.
  ///
  /// The thresholds for what to DO about a poor photo are deliberately NOT
  /// here - that's a domain rule and lives in `FoodRecognitionLogic`. This
  /// block only asks the model to report what it sees.
  static const String _imageQualityRules = '''
  IMAGE QUALITY - judge the PHOTO ITSELF, not how appetising the food looks:
    - sharpness: is the food in focus, or motion-blurred / out of focus?
    - lighting: well lit, too dark to see detail, or so bright that
      highlights are blown out and detail is lost?
    - colour: natural, or a strong unnatural cast (heavy yellow/orange/
      green/blue from artificial light) severe enough that the food's real
      colour cannot be judged?

  Then report:
    - "imageQuality": "good" | "acceptable" | "poor"
        "good"       = sharp, well lit, natural colour.
        "acceptable" = minor issues, dish still clearly identifiable.
        "poor"       = blurry, too dark, blown out, or strongly colour-cast
                       badly enough that identification is unreliable.
    - "imageQualityIssues": the specific problems, from exactly this list:
      ["blurry", "too_dark", "too_bright", "colour_cast", "low_detail"].
      Empty list when "imageQuality" is "good".

  If the photo is poor, still give your best guess - but LOWER "confidence"
  to match. A poor photo must NEVER produce a high-confidence answer.

  Judge quality by whether the DISH CAN BE IDENTIFIED, not by whether the
  photo is attractive. Dim warm restaurant lighting, a dark background, a
  blurred background with the food sharp, or a stylish/moody look are all
  "good" or "acceptable" as long as the food itself is legible. Reserve
  "poor" for photos where the food itself cannot be made out: the food is
  out of focus, so dark the food's own detail is lost, so bright the food
  is washed out, or so colour-cast the ingredients cannot be told apart.
  ''';

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
    final String prompt =
        '''
  Look at this food image and report:

  1. foodCount: how many SEPARATE, distinct food items/dishes are clearly
     visible? A single dish/plate/portion counts as one. Count distinct
     dishes, not every piece of food on one plate.

     What counts as ONE dish:
     - One plate/bowl/portion served as a single item = ONE, no matter how
       many components are on it. Nasi lemak (rice + sambal + anchovies +
       peanuts + egg + cucumber) is ONE dish, not five. Nasi campur / nasi
       kandar / banana leaf rice (rice with several side dishes on one plate)
       is ONE.
     - A main + its standard garnish, sauce, condiment or side = ONE.
     - A dish + a separate drink = ONE dish (ignore the drink unless the
       drink IS the subject, e.g. a photographed glass of cendol or teh tarik).
     - Count TWO or more ONLY when there are genuinely separate,
       independently ordered dishes in frame - e.g. a plate of char kway teow
       AND a separate bowl of laksa side by side.

     When in doubt, prefer 1. A false "too many foods" blocks a valid photo,
     which is worse than analysing the most prominent dish.

  2. dish: the MAIN dish name (when only one food is present). If you are
     not sure, give your best guess but set confidence low - NEVER invent a
     plausible-sounding dish for an unidentifiable photo.

  3. candidates: list up to 3 POSSIBLE dish names for the main food, most
     likely first, each with a confidence 0.0-1.0. If you are confident it
     is one dish, list only that one with a high confidence.

     These Malaysian dishes are commonly confused with each other. If the
     photo could plausibly be more than one of a group, list them as
     candidates rather than picking one confidently:
     - char kway teow / hokkien mee / mee goreng / kway teow goreng
     - asam laksa / curry laksa / Sarawak laksa / laksa Johor
     - nasi lemak / nasi campur / nasi kandar / banana leaf rice
     - roti canai / roti john / murtabak / roti telur
     - cendol / ais kacang (ABC) / bubur cha cha
     - mee rebus / mee bandung / mee soto
     - satay / chicken skewers of other cuisines
     - curry puff / epok-epok / samosa
     - kuih varieties (kuih lapis, seri muka, talam, kosui - very hard from
       a photo alone; prefer candidates over a confident single answer)

  4. Food detection status: "detected" | "not_detected" | "unclear"
     - use "unclear" when food is visible but you cannot confidently name it
     - never claim "detected" with a made-up dish

     WHEN TO GIVE UP: choose "unclear" (and confidence below 0.3) if ANY of
     these is true:
       - the photo is too blurry/dark to make out what the food is;
       - you can see food but cannot narrow it to fewer than ~4 possibilities;
       - the main subject is not food at all (a person, a menu, a signboard,
         an empty table, packaging with no visible food).
     "unclear" is a CORRECT and useful answer. Never invent a plausible dish
     name to avoid saying you don't know.

  5. Frame status: is the ENTIRE food visible within the frame?
     - "complete" if fully visible
     - "partially_captured" if cut off/partially outside frame
     - "obstructed" if blocked/unclear

$_localFoodRules

$_imageQualityRules

  Worked examples - match this reasoning style and calibration:

  Example A - a plate of coconut rice with sambal, anchovies, peanuts, egg:
  {"foodCount":1,"dish":"Nasi Lemak","candidates":[{"dish":"Nasi Lemak","confidence":0.94}],
   "localFoodReasoning":"Nasi lemak - Malaysian national dish, class (a).",
   "isMalaysianLocalFood":true,"localFoodConfidence":0.97,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.94}

  Example B - a boxed burger with branded fast-food packaging visible:
  {"foodCount":1,"dish":"Fast-food cheeseburger","candidates":[{"dish":"Fast-food cheeseburger","confidence":0.9}],
   "localFoodReasoning":"Western fast-food chain burger, branded packaging visible, no Malaysian identity - class (c).",
   "isMalaysianLocalFood":false,"localFoodConfidence":0.88,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.9}

  Example C - a burger in plain paper wrap, no branding, unclear origin:
  {"foodCount":1,"dish":"Burger","candidates":[{"dish":"Ramly burger","confidence":0.45},{"dish":"Fast-food cheeseburger","confidence":0.4}],
   "localFoodReasoning":"A burger, but no packaging or preparation cue shows whether it is a Malaysian Ramly-style burger or a generic one - class uncertain between (a) and (c).",
   "isMalaysianLocalFood":false,"localFoodConfidence":0.35,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.5}

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "foodCount": 1,
    "dish": "string",
    "candidates": [{"dish": "string", "confidence": 0.0-1.0}],
    "localFoodReasoning": "string",
    "isMalaysianLocalFood": boolean,
    "localFoodConfidence": 0.0-1.0,
    "imageQuality": "good|acceptable|poor",
    "imageQualityIssues": ["string"],
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
      localFoodConfidence: ((json['localFoodConfidence'] as num?) ?? 1)
          .toDouble(),
      localFoodReasoning: (json['localFoodReasoning'] as String?) ?? '',
      imageQuality: (json['imageQuality'] as String?) ?? 'good',
      imageQualityIssues:
          (json['imageQualityIssues'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
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
      ingredients: 'Coconut rice, sambal, peanuts, anchovies, boiled egg',
      origin: 'Melaka & Negeri Sembilan',
      cookingStyle: 'Simmering',
      mealType: 'Breakfast',
      foodCategory: 'Malay',
      isMalaysianLocalFood: true,
      culturalBackground: 'Traditional breakfast dish of the Malay Peninsula.',
      tasteTags: <String>['Spicy', 'Sweet', 'Rich'],
      mainTaste: 'Spicy',
      dietaryRestrictions: <String>[],
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
    final String prompt =
        '''
  Analyze this food image and extract the following information:

  1. Identify the dish name
  2. Identify the dish variant
  3. Provide a brief description
  3b. List the main ingredients, comma-separated (e.g. "rice, coconut milk,
      sambal, peanuts, anchovies, egg")
  4. Identify the origin/region
  5. Identify the cooking style
  6. Identify the meal type (Breakfast/Lunch/Dinner/Snack)
  7. Categorize: Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other
  8. Cultural background
  9. Taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3,
     plus "mainTaste": the single most important taste of the dish.

  9b. Dietary restrictions that apply to this dish - zero or more of the
      canonical `dietary_restriction` names (No Pork, No Beef, No Chicken,
      No Seafood, Vegetarian, Vegan, Halal, No Egg, No Dairy, No Gluten,
      No Nuts, No Shellfish, No Mayonnaise, No Mustard, ...). Use exactly
      these strings; use [] when none apply.

  10. Frame status: Is the ENTIRE food visible within the frame?
      - "complete" if fully visible
      - "partially_captured" if cut off/partially outside frame
      - "obstructed" if blocked/unclear

  11. Food detection status:
      - "detected" if food is clearly visible
      - "not_detected" if no food found
      - "unclear" if ambiguous

      WHEN TO GIVE UP: choose "unclear" (and confidence below 0.3) if ANY of
      these is true:
        - the photo is too blurry/dark to make out what the food is;
        - you can see food but cannot narrow it to fewer than ~4 possibilities;
        - the main subject is not food at all (a person, a menu, a signboard,
          an empty table, packaging with no visible food).
      "unclear" is a CORRECT and useful answer. Never invent a plausible dish
      name to avoid saying you don't know.

  12. Suggested selling price range for this dish in MYR (a typical stall /
      restaurant price): "suggestedPriceMin" and "suggestedPriceMax".

$_localFoodRules

$_imageQualityRules

  This is the IN-DEPTH analysis - your judgement here overrides any quicker
  first-pass guess, so take the full procedure above seriously rather than
  agreeing with an obvious first impression.

  Examine the image FRESH. Do not assume any earlier or more obvious reading
  is right. Before answering, actively consider at least one ALTERNATIVE
  dish it could be, and say in "localFoodReasoning" why you rejected it if
  you did. This call is the authoritative one - a quicker first pass may
  have been wrong, and correcting it here is exactly your job.

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "dish": "string",
    "variant": "string",
    "description": "string",
    "ingredients": "string",
    "origin": "string",
    "cookingStyle": "string",
    "mealType": "string",
    "foodCategory": "string",
    "localFoodReasoning": "string",
    "isMalaysianLocalFood": boolean,
    "localFoodConfidence": 0.0-1.0,
    "imageQuality": "good|acceptable|poor",
    "imageQualityIssues": ["string"],
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "mainTaste": "string",
    "dietaryRestrictions": ["string"],
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
      ingredients: (json['ingredients'] as String?) ?? '',
      origin: (json['origin'] as String?) ?? '',
      cookingStyle: (json['cookingStyle'] as String?) ?? '',
      mealType: (json['mealType'] as String?) ?? '',
      foodCategory: (json['foodCategory'] as String?) ?? '',
      isMalaysianLocalFood: (json['isMalaysianLocalFood'] as bool?) ?? false,
      localFoodConfidence: ((json['localFoodConfidence'] as num?) ?? 1)
          .toDouble(),
      localFoodReasoning: (json['localFoodReasoning'] as String?) ?? '',
      imageQuality: (json['imageQuality'] as String?) ?? 'good',
      imageQualityIssues:
          (json['imageQualityIssues'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      culturalBackground: (json['culturalBackground'] as String?) ?? '',
      tasteTags:
          (json['tasteTags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      mainTaste: (json['mainTaste'] as String?) ?? '',
      dietaryRestrictions:
          (json['dietaryRestrictions'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
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
  /// [name] is sent ALONGSIDE the image so Gemini VERIFIES the photo against
  /// that name (see the prompt - it is written to check the claim honestly,
  /// not to agree with it) and returns the details for exactly that one dish
  /// when the name matches. On a mismatch it reports what it actually sees
  /// ([FoodAnalysisResponse.nameMatchesPhoto] / [..observedFood]) instead of
  /// describing a dish that is not in the photo.
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
      ingredients: '',
      origin: '',
      cookingStyle: '',
      mealType: '',
      foodCategory: '',
      isMalaysianLocalFood: true,
      culturalBackground: '',
      tasteTags: const <String>[],
      mainTaste: '',
      dietaryRestrictions: const <String>[],
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
  A user believes the dish in this photo is called "$name". Your job is to
  CHECK that claim honestly, not to confirm it. The user may well be wrong.

  Step 1. Look at the photo BEFORE considering the name "$name" at all. In
          "observedFood", name the dish you actually see in 1-3 words (a
          menu-style label), e.g. "Nasi Lemak", "Pepperoni Pizza" - not a
          full description.
  Step 2. Now compare your observation with "$name". Could this photo
          reasonably be "$name"?
            - Consider regional spellings and alternative names for the same
              dish ("char kuey teow" = "char kway teow"; "ABC" = "ais
              kacang"). A spelling difference is a MATCH.
            - Consider variants of the same dish (nasi lemak with chicken vs
              with egg). A variant is a MATCH.
            - A genuinely different dish is a MISMATCH, even if both are
              Malaysian, and even if both are e.g. noodle dishes.
  Step 3. Report:
    - "nameMatchesPhoto": true only if the photo plausibly shows "$name".
    - "matchConfidence": 0.0-1.0, how sure you are of THAT verdict.
    - If "nameMatchesPhoto" is false, set "dish" to what you ACTUALLY see
      (your Step 1 observation), NOT to "$name". Do not describe a dish that
      is not in the photo.
    - If "nameMatchesPhoto" is true, set "dish" to "$name" and fill in the
      remaining fields for that dish as normal.

  Do not be agreeable. Saying "this photo does not show $name" when it does
  not is the CORRECT and most useful answer. A user who typed the wrong name
  is better served by being told than by being agreed with.

  When "nameMatchesPhoto" is true, provide the details for "$name":
    - variant, a brief description, main ingredients (comma-separated),
      origin/region, cooking style
    - meal type (Breakfast/Lunch/Dinner/Snack)
    - food category (Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other)
    - isMalaysianLocalFood (true/false)
    - cultural background
    - taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3,
      plus the single most important one as "mainTaste"
    - dietary restrictions - zero or more of the canonical names (No Pork,
      No Beef, No Chicken, No Seafood, Vegetarian, Vegan, Halal, No Egg,
      No Dairy, No Gluten, No Nuts, No Shellfish, No Mayonnaise, No Mustard,
      ...); use [] when none apply
    - a suggested selling price range in MYR (suggestedPriceMin and
      suggestedPriceMax)

  Return ONLY raw JSON, no markdown fences, no candidate list:
  {
    "observedFood": "string",
    "nameMatchesPhoto": boolean,
    "matchConfidence": 0.0-1.0,
    "dish": "string",
    "variant": "string",
    "description": "string",
    "ingredients": "string",
    "origin": "string",
    "cookingStyle": "string",
    "mealType": "string",
    "foodCategory": "string",
    "isMalaysianLocalFood": boolean,
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "mainTaste": "string",
    "dietaryRestrictions": ["string"],
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
      dish: (json['dish'] as String?) ?? name,
      variant: (json['variant'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      ingredients: (json['ingredients'] as String?) ?? '',
      origin: (json['origin'] as String?) ?? '',
      cookingStyle: (json['cookingStyle'] as String?) ?? '',
      mealType: (json['mealType'] as String?) ?? '',
      foodCategory: (json['foodCategory'] as String?) ?? '',
      isMalaysianLocalFood: (json['isMalaysianLocalFood'] as bool?) ?? false,
      culturalBackground: (json['culturalBackground'] as String?) ?? '',
      tasteTags:
          (json['tasteTags'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      mainTaste: (json['mainTaste'] as String?) ?? '',
      dietaryRestrictions:
          (json['dietaryRestrictions'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      foodStatus: (json['foodStatus'] as String?) ?? 'unclear',
      foodImageStatus: (json['foodImageStatus'] as String?) ?? 'unclear',
      priceMin: _asDouble(json['suggestedPriceMin']),
      priceMax: _asDouble(json['suggestedPriceMax']),
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
      nameMatchesPhoto: (json['nameMatchesPhoto'] as bool?) ?? true,
      matchConfidence: ((json['matchConfidence'] as num?) ?? 0).toDouble(),
      observedFood: (json['observedFood'] as String?) ?? '',
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

  // ===========================================================================
  // 3-step origin verification - the Option C gate (see
  // `FoodRecognitionLogic.registerNewDishes`). Text-only (dish name, no
  // image): asks THREE separately-framed questions so a single ingrained
  // model belief cannot just repeat itself. Port of
  // tools/validate_dish_origin.py.
  // ===========================================================================

  /// Dishes already confirmed wrong in this catalogue (port of the Python
  /// tool's KNOWN_MISATTRIBUTIONS). Append every newly-caught misattribution
  /// here - check 3 only gets more precise over time.
  static const List<String> knownMisattributions = <String>['Soto Ayam'];

  /// Check 1 - direct origin. No mention of Malaysia anywhere, so there is
  /// nothing for the model to anchor to or agree with. Asks for the historical
  /// origin AND the a/b/c/d case, so an adopted dish (roti canai) or a shared
  /// regional one (rendang) is not rejected just because its origin is not
  /// Malaysia.
  Future<Map<String, dynamic>> verifyOriginDirect(String dish) async {
    if (!useLiveGemini) {
      return <String, dynamic>{
        'case': 'a',
        'origin_country': 'Malaysia',
        'origin_ethnicity': 'Malay',
        'confidence': 0.9,
      };
    }
    final String prompt =
        'Classify the dish "$dish" against this scheme, using culinary '
        'history, not where it is eaten today:\n'
        '(a) MALAYSIAN ORIGIN - the dish originated in Malaysia.\n'
        '(b) ADOPTED / NATURALIZED - originated elsewhere but adopted and '
        'naturalized as everyday Malaysian local food (e.g. roti canai, '
        'chee cheong fun).\n'
        '(c) FOREIGN - popular in Malaysia but foreign with no distinct '
        'Malaysian identity (e.g. sushi, pizza, a Western fast-food '
        'burger).\n'
        '(d) SHARED REGIONAL - shared across Malaysia/Indonesia/etc. and '
        'genuinely part of Malaysian everyday food culture (e.g. rendang, '
        'laksa).\n\n'
        'What country/ethnic cuisine did it historically originate from, '
        'and which case fits best?\n\n'
        'Return strictly this JSON object, nothing else, no markdown fences: '
        '{"case": "a|b|c|d", "origin_country": "<country>", '
        '"origin_ethnicity": "<e.g. Malay, Javanese, Peranakan, Thai>", '
        '"confidence": <0.0-1.0>}';
    final String raw = await _gemini.generateText(
      prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    return _decodeJsonObject(raw);
  }

  /// Check 2 - devil's advocate. Surfaces the Malaysia-vs-elsewhere dispute
  /// and asks the model to adjudicate it, case-aware: a dish can be
  /// Malaysian local food even when it did not originate in Malaysia.
  Future<Map<String, dynamic>> verifyOriginAdjudicate(String dish) async {
    if (!useLiveGemini) {
      return <String, dynamic>{
        'case': 'a',
        'actual_origin_country': 'Malaysia',
      };
    }
    final String prompt =
        'Some sources describe "$dish" as Malaysian, others as originating '
        'elsewhere (Indonesia, Singapore, Thailand, Brunei, India, China, '
        '...). Some dishes are adopted/naturalized in Malaysia (roti canai, '
        'chee cheong fun) or shared regional (rendang, laksa) and are '
        'genuinely Malaysian local food even though they did not originate '
        'there.\n\n'
        'Adjudicate which case fits best:\n'
        '(a) MALAYSIAN ORIGIN\n'
        '(b) ADOPTED / NATURALIZED in Malaysia (everyday local food, foreign '
        'origin)\n'
        '(c) FOREIGN with no distinct Malaysian identity\n'
        '(d) SHARED REGIONAL, genuinely part of Malaysian everyday food '
        'culture\n\n'
        'Return strictly this JSON object, nothing else, no markdown fences: '
        '{"case": "a|b|c|d", "actual_origin_country": "<country>", '
        '"distinguishing_notes": "<max 2 sentences>"}';
    final String raw = await _gemini.generateText(
      prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    return _decodeJsonObject(raw);
  }

  /// Check 3 - known pattern. Audits against the specific recurring failure
  /// already caught, rather than a generic origin question.
  Future<Map<String, dynamic>> verifyOriginKnownPattern(String dish) async {
    if (!useLiveGemini) {
      return <String, dynamic>{'is_commonly_misattributed': false};
    }
    final String examples = knownMisattributions.join(', ');
    final String prompt =
        'You are auditing a Malaysian local-food database for a specific, '
        'recurring error: dishes that are genuinely eaten across Malaysia '
        'get mislabeled as "Malay/Malaysian in origin" even though they '
        'actually originated elsewhere. Confirmed examples of this exact '
        'mistake caught in this database so far: $examples.\n\n'
        'Is "$dish" the same kind of mistake?\n\n'
        'Return strictly this JSON object, nothing else, no markdown fences: '
        '{"is_commonly_misattributed": <true/false>, '
        '"correct_origin_if_misattributed": "<country or null>", '
        '"reasoning": "<max 2 sentences>"}';
    final String raw = await _gemini.generateText(
      prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
    );
    return _decodeJsonObject(raw);
  }
}
