import 'dart:convert';

import '../../app/config/env.dart';
import '../../model/data_models/food_analysis_response.dart';
import '../../model/data_models/place_photo_match_response.dart';
import '../../model/data_models/signboard_analysis_response.dart';
import '../../model/data_models/signboard_name_match_response.dart';
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

  /// The local/foreign flag the app trusts: the single-letter `localClass`
  /// the model reported in Step 3 ("a"/"b" = Malaysian, "c"/"d" = not),
  /// falling back to `isMalaysianLocalFood` when no letter came back. Lite
  /// models occasionally write a boolean that CONTRADICTS the class they
  /// chose; the one-letter classification is the simpler, more reliable
  /// output, so it is the flag of record.
  static bool _isLocalFromClass(Object? jsonClass, Object? fallback) {
    final String value = (jsonClass as String?)?.trim().toLowerCase() ?? '';
    if (value.startsWith('a') || value.startsWith('b')) return true;
    if (value.startsWith('c') || value.startsWith('d')) return false;
    return (fallback as bool?) ?? false;
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
  ///    genuinely borderline local-ness call still looked fully certain;
  ///  - and it accepted ANY "Malaysian hawker/street adaptation", so a
  ///    foreign original sold here unchanged (tau fu fah) passed as local
  ///    food - see the MERGED-FOOD RULE below, added 2026-09-13.
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
        Korean fried chicken, plain Western steak, doughnuts, french toast,
        pancakes.
    (d) UNIDENTIFIABLE - you genuinely cannot tell what the dish is.

  Step 4. Report all four of these:
    - "localClass": EXACTLY ONE letter - "a", "b", "c" or "d" - the class
      you chose in Step 3. One letter only, never a word, a range or two
      letters.
    - "localFoodReasoning": ONE short sentence - the dish, its origin, and
      the class letter you chose. e.g. "Ramly burger - Malaysian street
      adaptation sold at roadside stalls, class (a)."
    - "isMalaysianLocalFood": true for (a) and (b); false for (c) and (d) -
      it must AGREE with "localClass". If they disagree, the class letter
      is the correct one and the boolean is the mistake.
    - "localFoodConfidence": 0.0-1.0 - how sure you are of THIS judgement
      specifically. This is SEPARATE from "confidence" (how sure you are of
      the dish NAME). A clearly-photographed burger may score high
      "confidence" but low "localFoodConfidence" if you cannot tell whether
      it is a Ramly-style or a Western-chain burger.

  CRITICAL: being sold in Malaysia does NOT make a dish Malaysian. A burger
  from a Western chain is class (c); a Ramly burger is class (a). If you
  cannot distinguish which the photo shows, say so with a LOW
  "localFoodConfidence" rather than guessing true.

  KOPITIAM CAVEAT: serving a dish at a kopitiam, mamak or roadside stall
  does not make it class (a). Kaya toast, roti bakar and half-boiled eggs
  ARE Malaysian kopitiam food (class (a)); a Western breakfast cooked the
  same way - french toast, pancakes - is still a foreign dish (class (c)).
  Judge the DISH, never the venue.

  MERGED-FOOD RULE: a dish that is originally foreign may be class (a) or
  (b) ONLY once it has FULLY MERGED - Malaysia reshaped it into a form of
  its own. yong tau foo: Chinese stuffed tofu reworked in Malaysia around
  fish paste and sold from Malaysian stalls, so it IS local food. A dish
  still served in its ORIGINAL foreign form, with no Malaysian evolution of
  its own, has NOT fully merged and is NOT local food however widely it
  sells here - tau fu fah (soft tofu pudding as made in China) stays class
  (c). Selling at pasar malam or kopitiams is NOT a Malaysian form.

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

  /// Shared prompt block defining the app's catalogue dish types. Added so
  /// recognition follows the SAME categories the catalogue actually stores:
  /// a genuinely Malaysian snack or packaged item (e.g. Tam Tam biscuits)
  /// must not be offered as an addable landmark even though it is a real
  /// Malaysian product.
  static const String _catalogueFoodTypeRules = '''
  CATALOGUE DISH TYPE - classify the detected item into EXACTLY ONE of the
  five dish types the app's local-food catalogue accepts:

  - "Food" - a MAIN DISH / meal served on a plate/bowl/wrapper: rice dishes
    (nasi lemak, nasi kandar, nasi campur), noodles (char kway teow, laksa,
    mee goreng), roti (roti canai, murtabak, roti john), etc. Something a
    person orders to eat as a meal.
  - "Beverage" - a REAL DRINK served in a cup/glass: teh tarik, kopi, fresh
    juice, cendol-as-drink. NOT a canned ("tin") or bottled drink, and NOT a
    packaged drink.
  - "Fruit" - fresh whole or cut fruit (a plate of cut mango, a young
    coconut).
  - "Dessert" - a sweet dish (ais kacang, cendol-as-dessert, bubur cha cha).
  - "Kuih" - traditional Malay cakes/sweets/rice-based snacks served fresh
    (kuih lapis, seri muka, talam, onde-onde, apam balik).

  Use "none" when the item is NOT any of the above - for example:
    - packaged snacks (biscuits like Tam Tam, chips/crisps, crackers,
      cookies, chocolates, sweets in packaging)
    - canned or bottled drinks (soft drinks in a "tin", bottled water,
      packaged juice)
    - packaged/instant foods with no freshly-served dish
    - any non-food item.

  A "none" item may still be genuinely Malaysian, but it is a Malaysian
  product, NOT an addable dish: it must never be offered as a landmark.
  Set "foodType" to exactly one of: Food|Beverage|Fruit|Dessert|Kuih|none.
  ''';

  /// Concrete VISUAL differentiators for the dish clusters the lite model
  /// most often confuses - a murtabak photo read as "french toast" was a
  /// user-reported failure. Weak models cannot reliably apply cultural
  /// knowledge, but they CAN compare what is visible: shape, the filling at
  /// the cut edge, and the sides plated with it. Shared by the quick, full
  /// and verification prompts.
  static const String _lookalikeRules = '''
  CONFUSABLE LOOKALIKES - decide by VISIBLE SHAPE, FILLING and SIDES:
  - murtabak: a thick folded/squared flatbread enclosing a savoury filling
    (minced meat, onion, egg). The CUT EDGE shows filling layers, and it is
    normally served with curry/dal or pickled onion - not syrup.
  - roti canai / roti telur: a soft round flaky flatbread eaten with curry,
    plain or egg-coated - not a thick stack of soaked bread.
  - roti john: a LONG baguette-style roll omelette sandwich eaten with
    chilli sauce; long and loaf-shaped, not square.
  - french toast / pancakes / waffles: triangular bread slices or a stack
    of round fluffy pieces, eggy-yellow and soaked-soft or fluffy, with
    butter/syrup/honey - and NO curry, dal or pickled onion beside them.
  - kaya toast: thin TOASTED bread slices with a green/brown coconut-jam
    filling, with half-boiled eggs and kopi/teh - not syrup.
  A murtabak is NOT french toast just because it is flat bread with egg:
  check the cut surface, the filling, and what is served beside it.
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

  2b. visualEvidence: BEFORE you finalise the name, note the key VISIBLE
     FEATURES you are using - shape/form, colour, filling or cut surface,
     and any side, sauce or packaging plated with it. 1-2 short phrases,
     not a general description. When a similar dish could fit, name that
     dish and the visible feature that rules it out (see CONFUSABLE
     LOOKALIKES below).

  2c. suggestedPriceMin / suggestedPriceMax: the typical selling-price range
     for that dish in Malaysia, in MYR (a stall price up to a restaurant
     price, e.g. 4.5 and 8.5). Whole ringgit is fine. Use 0 and 0 when you
     cannot estimate - never invent a range for an unidentifiable photo.

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

$_catalogueFoodTypeRules

$_lookalikeRules

  Worked examples - match this reasoning style and calibration:

  Example A - a plate of coconut rice with sambal, anchovies, peanuts, egg:
  {"visualEvidence":"white rice heap with red sambal, fried anchovies, peanuts, boiled egg and cucumber slices on one plate","foodCount":1,"dish":"Nasi Lemak","candidates":[{"dish":"Nasi Lemak","confidence":0.94}],
   "localClass":"a",
   "localFoodReasoning":"Nasi lemak - Malaysian national dish, class (a).",
   "isMalaysianLocalFood":true,"localFoodConfidence":0.97,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.94}

  Example B - a boxed burger with branded fast-food packaging visible:
  {"visualEvidence":"burger inside a branded fast-food box and paper wrapper, no local stall cues","foodCount":1,"dish":"Fast-food cheeseburger","candidates":[{"dish":"Fast-food cheeseburger","confidence":0.9}],
   "localClass":"c",
   "localFoodReasoning":"Western fast-food chain burger, branded packaging visible, no Malaysian identity - class (c).",
   "isMalaysianLocalFood":false,"localFoodConfidence":0.88,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.9}

  Example C - a burger in plain paper wrap, no branding, unclear origin:
  {"visualEvidence":"plain paper-wrapped burger, no branding or stall cues visible","foodCount":1,"dish":"Burger","candidates":[{"dish":"Ramly burger","confidence":0.45},{"dish":"Fast-food cheeseburger","confidence":0.4}],
   "localClass":"c",
   "localFoodReasoning":"A burger, but no packaging or preparation cue shows whether it is a Malaysian Ramly-style burger or a generic one - cannot tell, so reported as (c) with low confidence.",
   "isMalaysianLocalFood":false,"localFoodConfidence":0.35,
   "imageQuality":"good","imageQualityIssues":[],
   "foodStatus":"detected","foodImageStatus":"complete","confidence":0.5}

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "visualEvidence": "string",
    "foodCount": 1,
    "dish": "string",
    "candidates": [{"dish": "string", "confidence": 0.0-1.0}],
    "localClass": "a|b|c|d",
    "localFoodReasoning": "string",
    "isMalaysianLocalFood": boolean,
    "localFoodConfidence": 0.0-1.0,
    "suggestedPriceMin": 0.0,
    "suggestedPriceMax": 0.0,
    "imageQuality": "good|acceptable|poor",
    "imageQualityIssues": ["string"],
    "foodType": "Food|Beverage|Fruit|Dessert|Kuih|none",
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
      // Deterministic, strict-JSON landmark read: temperature 0 means the
      // same photo gets the same (most probable) answer instead of a fresh
      // sample per attempt; thinkingBudget is opt-in via
      // GEMINI_THINKING_BUDGET (0 = off).
      temperature: 0,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'quick',
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
      foodType: (json['foodType'] as String?) ?? '',
      // The class letter the model chose ("a"/"b" local, "c"/"d" not) is
      // the flag of record; the boolean is only a fallback.
      isMalaysianLocalFood: _isLocalFromClass(
        json['localClass'],
        json['isMalaysianLocalFood'],
      ),
      localFoodConfidence: ((json['localFoodConfidence'] as num?) ?? 1)
          .toDouble(),
      localFoodReasoning: (json['localFoodReasoning'] as String?) ?? '',
      imageQuality: (json['imageQuality'] as String?) ?? 'good',
      imageQualityIssues:
          (json['imageQualityIssues'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      // The quick call asks for the same suggested range the full call does,
      // so a catalogue fast-path result still has one - see
      // `FoodRecognitionLogic.recognizeFood`.
      priceMin: _asDouble(json['suggestedPriceMin']),
      priceMax: _asDouble(json['suggestedPriceMax']),
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

  /// The STORED CATALOGUE RECORD block for [stored] - empty when the app does
  /// not know which dish the photo shows (see [StoredDishPrompt]).
  ///
  /// This is context, never a verdict: the model still reads the photo itself.
  /// The point is that the app already HAS the dish's text, so the answer
  /// either confirms it verbatim or adapts it to the variant actually shown -
  /// it never re-invents the plain dish from scratch.
  static String _storedDishRules(StoredDishPrompt? stored) {
    if (stored == null) return '';
    return '''
  STORED CATALOGUE RECORD - the app has already saved this dish:
    dish: ${stored.name}
    category: ${stored.category}
    description: ${stored.description}
    ingredients: ${stored.ingredients}
    cultural background: ${stored.culturalBackground}

  Treat the record as the BASE of your answer:
    - if the photo shows EXACTLY that dish, return its stored category,
      description, ingredients and cultural background UNCHANGED - never
      rewrite, shorten or "improve" text that is still true;
    - if the photo shows a VARIANT the record does not describe ("Siew Yoke
      Nasi Lemak" over "Nasi Lemak"), ADAPT those fields to the dish
      actually shown: change what the variant changes (the ingredients gain
      the variant's own ones, the category/culture move to the tradition it
      belongs to) and keep every part of the record the variant does not
      affect;
    - never turn the record into an answer of its own: it is background, and
      your own observation of the photo still decides the dish (and, for a
      typed name, whether the photo matches that name).
''';
  }

  /// Full call - phase 2, only reached when the dish from [identifyFoodName]
  /// isn't already in the catalogue (REQ106_2, REQ106_7).
  /// Returns: dish, variant, origin, category, meal type, frame status, etc.
  /// [storedDish] is the curated row the app already matched for this dish
  /// (when there is one) - it rides the prompt so the answer describes the
  /// dish AS SHOWN: the stored text echoed where it still holds, adapted where
  /// the variant changes it (see [_storedDishRules]).
  /// Errors: A2 (timeout), A3 (not local food), A4 (no food), A18 (incomplete)
  Future<FoodAnalysisResponse> analyzeFoodImage({
    required List<int> imageBytes,
    StoredDishPrompt? storedDish,
  }) async {
    if (useLiveGemini) {
      return _analyzeFoodImageLive(imageBytes, storedDish);
    }

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
      pronunciation: 'nah-see luh-mak',
    );
  }

  Future<FoodAnalysisResponse> _analyzeFoodImageLive(
    List<int> imageBytes,
    StoredDishPrompt? storedDish,
  ) async {
    final String prompt =
        '''
  Analyze this food image and extract the following information:

  1. Identify the dish name
  1b. visualEvidence: the key VISIBLE FEATURES you used to name it -
      shape/form, colour, filling or cut surface, and any side, sauce or
      packaging plated with it (1-2 short phrases, not a description).
      When a similar dish could fit, name it and the visible feature that
      rules it out - see CONFUSABLE LOOKALIKES below.
  2. Identify the dish variant
  3. Provide a brief description
  3b. ingredients: the main ingredients of the dish AS SHOWN IN THIS PHOTO,
      comma-separated (e.g. "rice, coconut milk, sambal, peanuts, anchovies,
      egg"). When the photo shows a VARIANT (step 2), the ingredient(s) that
      make it that variant MUST be in the list too (e.g. a "Cendol Jagung"
      photo adds "sweet corn"; a "Nasi Lemak Ayam" photo adds "fried
      chicken"; a "Siew Yoke Nasi Lemak" photo adds "siew yoke (roast
      pork)") - the list names what makes it THAT variant. Never list only
      the base dish's ingredients when the variant adds its own.

  3c. aliases: list up to 4 WELL-KNOWN alternative names of the dish you
      identified - genuine other names/scripts/spellings of the SAME dish
      (e.g. for bubur cha cha: "摩摩喳喳", "Bubur Chacha", "Bobochacha"; for
      ais kacang: "ABC"; for pulut hitam: "Bee Koh Moy"). Rules: only real,
      established names of the SAME dish - never a different dish, never a
      description, an ingredient list or a made-up translation. Use [] when
      you do not know reliable aliases.

  3d. pronunciation: how the dish name is SAID, written so a text-to-speech
      voice reads it correctly - a simple phonetic respelling in lowercase
      Latin letters and hyphens (e.g. "nah-see luh-mak" for Nasi Lemak,
      "chah kway teow" for Char Kway Teow, "moh moh zha zha" for 摩摩喳喳,
      "roh-tee chah-nai" for Roti Canai). Use the dish's common spoken form,
      not a literal letter-by-letter reading. Empty string when the name is
      already spoken exactly as written.

  4. Identify the origin/region
  5. Identify the cooking style
  6. Identify the meal type - EXACTLY ONE of the catalogue's own values,
     spelled exactly as listed: All-Day Dining | Breakfast | Lunch | High
     Tea | Dinner | Supper | Street Food | Dessert | Beverage (Beverage for
     drinks). Never invent another value.
  7. Categorize: Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other
  8. Cultural background
  9. Taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3,
     plus "mainTaste": the single most important taste of the dish.

  9b. Dietary restrictions that CONFLICT with this dish - zero or more of
      the canonical `dietary_restriction` names (No Pork, No Beef, No
      Chicken, No Seafood, Vegetarian, Vegan, Halal, No Egg, No Dairy, No
      Gluten, No Nuts, No Shellfish, No Mayonnaise, No Mustard, ...). Use
      exactly these strings; use [] when none apply.

      CRITICAL: list a restriction ONLY when the dish CONTAINS an ingredient
      that the restriction forbids (e.g. "No Pork" for a pork dish, "No
      Coconut" when it is cooked with coconut milk). NEVER list a restriction
      merely because the dish is free of it - a pork-free or gluten-free or
      egg-free dish is NOT tagged No Pork / No Gluten / No Egg. When in
      doubt, prefer a shorter list over a longer one. A VARIANT that adds an
      ingredient adds its restriction too: a "Siew Yoke Nasi Lemak" contains
      roast pork, so it is tagged "No Pork" even though plain nasi lemak is
      not - judge the variant actually shown, not the base dish alone.

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

${_storedDishRules(storedDish)}
$_localFoodRules

$_imageQualityRules

$_catalogueFoodTypeRules

$_lookalikeRules

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
    "visualEvidence": "string",
    "dish": "string",
    "variant": "string",
    "description": "string",
    "ingredients": "string",
    "origin": "string",
    "cookingStyle": "string",
    "mealType": "string",
    "foodCategory": "string",
    "foodType": "Food|Beverage|Fruit|Dessert|Kuih|none",
    "localClass": "a|b|c|d",
    "localFoodReasoning": "string",
    "isMalaysianLocalFood": boolean,
    "localFoodConfidence": 0.0-1.0,
    "imageQuality": "good|acceptable|poor",
    "imageQualityIssues": ["string"],
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "mainTaste": "string",
    "dietaryRestrictions": ["string"],
    "aliases": ["string"],
    "pronunciation": "string",
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
      temperature: 0,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'full',
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
      foodType: (json['foodType'] as String?) ?? '',
      isMalaysianLocalFood: _isLocalFromClass(
        json['localClass'],
        json['isMalaysianLocalFood'],
      ),
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
      aliases:
          (json['aliases'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      foodCount: (json['foodCount'] as num?)?.toInt() ?? 1,
      pronunciation: (json['pronunciation'] as String?) ?? '',
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
  /// [storedDish] is the curated row the app already matched for the typed
  /// dish (when there is one) - it rides the prompt as the STORED CATALOGUE
  /// RECORD, so a typed VARIANT comes back adapted to the dish actually shown
  /// while the record itself never decides the match (see [_storedDishRules]).
  /// Errors: A2 (timeout)
  Future<FoodAnalysisResponse> analyzeFoodWithName({
    required List<int> imageBytes,
    required String name,
    StoredDishPrompt? storedDish,
  }) async {
    if (useLiveGemini) {
      return _analyzeFoodWithNameLive(imageBytes, name, storedDish);
    }

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
      pronunciation: name,
    );
  }

  Future<FoodAnalysisResponse> _analyzeFoodWithNameLive(
    List<int> imageBytes,
    String name,
    StoredDishPrompt? storedDish,
  ) async {
    final String prompt =
        '''
  A user believes the dish in this photo is called "$name". Your job is to
  CHECK that claim honestly, not to confirm it. The user may well be wrong.

  Step 1. Look at the photo BEFORE considering the name "$name" at all. In
          "observedFood", name the dish you actually see in 1-3 words (a
          menu-style label), e.g. "Nasi Lemak", "Pepperoni Pizza" - not a
          full description. Also fill "visualEvidence" with the key visible
          features behind your read - shape/form, colour, filling or cut
          surface, sides/sauce - and, when a similar dish could fit, the
          feature that rules it out (see CONFUSABLE LOOKALIKES).
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
    - variant, a brief description, main ingredients of "$name" (comma-
      separated; include what makes the typed variant that variant - a
      "Cendol Jagung" adds "sweet corn", a "Siew Yoke Nasi Lemak" adds
      "siew yoke (roast pork)"), origin/region, cooking style
    - meal type - EXACTLY ONE of the catalogue's own values: All-Day Dining,
      Breakfast, Lunch, High Tea, Dinner, Supper, Street Food, Dessert or
      Beverage (Beverage for drinks; never invent another value)
    - food category (Malay|Chinese|Indian|Nyonya|Sabah|Sarawak|Other)
    - localClass ("a"|"b"|"c"|"d" per the local-food rules above) and
      isMalaysianLocalFood (true for a/b, false for c/d - they must agree)
    - cultural background
    - taste/flavour tags (e.g. Spicy, Sweet, Rich, Savoury, Sour) - up to 3,
      plus the single most important one as "mainTaste"
    - dietary restrictions that CONFLICT with this dish - zero or more of
      the canonical names (No Pork, No Beef, No Chicken, No Seafood,
      Vegetarian, Vegan, Halal, No Egg, No Dairy, No Gluten, No Nuts, No
      Shellfish, No Mayonnaise, No Mustard, ...); use [] when none apply.
      CRITICAL: list a restriction ONLY when the dish CONTAINS an ingredient
      that restriction forbids; NEVER list one the dish is free of (a
      gluten-free dish is not tagged No Gluten). A VARIANT that adds an
      ingredient adds its restriction too - a "Siew Yoke Nasi Lemak"
      contains roast pork, so it is tagged "No Pork".
    - a suggested selling price range in MYR (suggestedPriceMin and
      suggestedPriceMax)
    - aliases: up to 4 well-known ALTERNATIVE names of the SAME dish (other
      languages/scripts/spellings - e.g. "摩摩喳喳"/"Bubur Chacha" for bubur
      cha cha, "ABC" for ais kacang, "Bee Koh Moy" for pulut hitam). Only
      genuine established names of the SAME dish - never a different dish, a
      description or a made-up translation. [] when unknown.
    - pronunciation: how the dish name is SAID, written so a text-to-speech
      voice reads it correctly - a simple phonetic respelling in lowercase
      Latin letters and hyphens (e.g. "nah-see luh-mak" for Nasi Lemak,
      "chah kway teow" for Char Kway Teow, "moh moh zha zha" for 摩摩喳喳).
      Use the dish's common spoken form, not a literal letter-by-letter
      reading. Empty string when the name is already spoken as written.

${_storedDishRules(storedDish)}
$_localFoodRules

$_lookalikeRules

$_catalogueFoodTypeRules

  Return ONLY raw JSON, no markdown fences, no candidate list:
  {
    "visualEvidence": "string",
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
    "foodType": "Food|Beverage|Fruit|Dessert|Kuih|none",
    "localClass": "a|b|c|d",
    "isMalaysianLocalFood": boolean,
    "culturalBackground": "string",
    "tasteTags": ["string"],
    "mainTaste": "string",
    "dietaryRestrictions": ["string"],
    "aliases": ["string"],
    "pronunciation": "string",
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
      // Deterministic verdict: the SAME photo + typed name must get the same
      // answer on every attempt. Without this the model samples at its
      // default temperature, so re-typing the same name could "roll" a
      // different observed dish (murtabak vs roti john on the same photo).
      temperature: 0,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'verify',
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
      foodType: (json['foodType'] as String?) ?? '',
      isMalaysianLocalFood: _isLocalFromClass(
        json['localClass'],
        json['isMalaysianLocalFood'],
      ),
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
      aliases:
          (json['aliases'] as List<dynamic>?)?.whereType<String>().toList() ??
          const <String>[],
      nameMatchesPhoto: (json['nameMatchesPhoto'] as bool?) ?? true,
      matchConfidence: ((json['matchConfidence'] as num?) ?? 0).toDouble(),
      observedFood: (json['observedFood'] as String?) ?? '',
      foodCount: 1,
      pronunciation: (json['pronunciation'] as String?) ?? '',
    );
  }

  /// Whether a MANUALLY TYPED dish name is a MISSPELLING of the dish the
  /// photo showed - the "Show this food" flow's spelling gate (see
  /// `FoodRecognitionLogic.resolveByName`). Text-only: by the time it runs,
  /// Gemini has already confirmed the photo shows [observedFood] and the
  /// tourist typed [typedName] for it; the only open question is the
  /// SPELLING.
  ///
  /// A regional/alternative spelling of the same dish ("char kuey teow" =
  /// "char kway teow") is NOT a typo; a misspelling ("prok belly" for
  /// "Pork Belly") is. The verdict is accepted only TOGETHER with a
  /// corrected spelling - `isTypo` without a `correctedName` is reported as
  /// "no typo", so a half-answer can never block or rewrite what the
  /// tourist typed.
  Future<({bool isTypo, String correctedName})> checkTypedNameSpelling({
    required String typedName,
    required String observedFood,
  }) async {
    if (!useLiveGemini) return (isTypo: false, correctedName: '');
    final String prompt =
        '''
  A tourist typed a dish name by hand into a food app. The photo has
  already been verified to show "$observedFood"; the tourist typed
  "$typedName" for it.

  Answer ONE question: is "$typedName" a MISSPELLING (a typo) of
  "$observedFood"?

  - A TYPO is the same name written with wrong letters - "prok belly" for
    "Pork Belly", "murtabakk" for "Murtabak", "chee cheong funn" for
    "Chee Cheong Fun". The same dish, misspelled.
  - An ESTABLISHED alternative name or spelling is NOT a typo: regional
    spellings ("char kuey teow" = "char kway teow"), other names ("ABC" =
    "ais kacang"), translations, other languages/scripts for the SAME
    dish, or a variant of it (nasi lemak with chicken vs with egg). NEVER
    flag these.
  - A genuinely DIFFERENT dish is NOT a typo - a different name is not a
    misspelling.
  - When in doubt, it is NOT a typo.

  Return ONLY raw JSON, no markdown fences:
  {
    "isTypo": boolean,
    "correctedName": "string"
  }
  "correctedName" is the correctly spelled name of the SAME dish when
  "isTypo" is true, and "" otherwise.
  ''';
    final String raw = await _gemini.generateText(
      prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
      label: 'spelling',
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    final String corrected = (json['correctedName'] as String?)?.trim() ?? '';
    final bool isTypo = json['isTypo'] == true && corrected.isNotEmpty;
    return (isTypo: isTypo, correctedName: isTypo ? corrected : '');
  }

  /// Analyze signboard image to extract restaurant name (REQ106_31, REQ106_37)
  /// Returns: extracted text + frame status. Multilingual-aware - Malaysian
  /// signs mix Malay/English (Latin), Chinese, Tamil and Jawi; the prompt
  /// romanises non-Latin names into [SignboardAnalysisResponse.textDetected]
  /// and keeps the exact displayed text in
  /// [SignboardAnalysisResponse.nameOriginalScript], with
  /// [SignboardAnalysisResponse.scriptVariant] describing the style actually
  /// painted on the sign so a "turned" transcription can be caught.
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

  Malaysian signboards commonly mix scripts: Malay and English (Latin),
  Simplified/Traditional Chinese, Tamil, and Jawi (Malay written in Arabic
  script). Read text in ALL of these scripts - never refuse or report
  "unreadable" just because the name is not in Latin letters.

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
  3. Identify the RESTAURANT NAME - usually the largest, most prominent
     text on the signboard. Return ONLY the name. NEVER include:
       - lot numbers or addresses ("Lot 12", "Lot No. 12", "No. 12",
         "Jalan Ampang", "Jln Tun Razak", postcodes like "50450")
       - phone numbers ("Tel: 012-345 6789", "HP 0123456789",
         "+60 12-345 6789")
       - slogans, "Open"/"Buka" signs, or operating hours.
     When words like "Restoran", "Restaurant", "Kedai", "Kopitiam",
     "茶餐室" are part of the name, KEEP them - do not strip or drop them.
     If a lot number or phone number appears on the signboard, leave it
     out of "textDetected" entirely.
  4. Transcribe the name faithfully from the signboard - the form you
     DETECTED is the form you RETURN, never the one you prefer:
       - If you detected Traditional Chinese, return Traditional Chinese.
         If you detected Simplified Chinese, return Simplified Chinese.
         NEVER convert between them, in either direction: if the sign
         paints 樓, return 樓 - not 楼; if it paints 记, return 记 - not
         記 (same for every pair: 麵/面, 雞/鸡, 館/馆, ...). Write the
         painted variant even when you would normally write the other one.
       - Judge each character by its STROKES, not by its meaning: the
         complex form is Traditional (義 has many strokes), the reduced
         form is Simplified (义 has three). Example: the characters painted
         天義 MUST come back as 天義 - never 天义; the characters painted
         天义 MUST come back as 天义 - never 天義. The reading is
         identical either way, so the reading must never decide the
         characters - only the painted glyphs decide.
       - The SAME rule applies to EVERY language and script, not just
         Chinese: copy Jawi as Jawi, Tamil as Tamil, English/Malay exactly
         as written, and unusual or old spellings exactly as painted.
         Never transliterate, and never switch a script or a spelling to
         the form you prefer - your preference is not part of the photo.
       - Never reorder, add or drop characters, and keep the punctuation
         and spacing as painted.
  5. Before returning, re-read your transcription character by character
     against the signboard: fix any character you substituted, and make
     sure the characters you are about to return ARE the variant you
     report in "scriptVariant" - Traditional characters for a
     "traditional" sign, Simplified characters for a "simplified" sign,
     never the other way round. For every character whose stroke count
     you are unsure of, look at the signboard again and return the glyph
     that is painted there, not the glyph you would normally write.

  For non-Latin names (Chinese/Tamil/Jawi):
  - "textDetected" = the romanised (Latin) form using the most common
    Malaysian spelling (pinyin for Chinese, romanised Tamil/Jawi). If
    unsure, transcribe phonetically so it is still usable in the app.
  - "nameOriginalScript" = the name exactly as it is painted on the
    signboard (see step 4 - Traditional stays Traditional, Simplified
    stays Simplified). Copy EVERY painted line of the name into this
    field, in reading order: when the sign paints Chinese characters with
    a Latin line such as "Tian Yi" beneath them, the whole painted name
    goes here - "天義 Tian Yi". A line painted on the signboard is part
    of the name, not a translation; never add a Latin line that is not
    painted, and never drop one that is.
  - "scriptVariant" = the Chinese style ACTUALLY PAINTED on the signboard,
    read off the sign in the image - "simplified" | "traditional" | "mixed"
    (the sign itself mixes both styles) | "n/a" (name is not Chinese). Take
    it from the painted glyphs, NOT from what you would normally write -
    and "nameOriginalScript" MUST match it: the transcription and this
    label can never disagree (a Traditional sign returned in Simplified
    characters - or the reverse - is a failure of this task).
  For Latin-script names both fields carry the same text and
  "languageScript" is "latin".

  IMPORTANT: the name being readable does NOT mean the signboard is fully in
  frame. Judge completeness ONLY by whether any part of the signboard is
  clipped at the image edges.

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "signboardStatus": "detected|not_detected|unclear",
    "scriptVariant": "simplified|traditional|mixed|n/a - decide this style FIRST",
    "textDetected": "restaurant name only - no lot number, address, or phone number, or null",
    "nameOriginalScript": "the name exactly as painted - every painted line in reading order (e.g. 天義 Tian Yi), in the style decided above, or null if the name is Latin",
    "languageScript": "latin|chinese|tamil|jawi|mixed",
    "signboardImageStatus": "complete|partially_captured|obstructed",
    "confidence": 0.0-1.0
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'signboard',
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return SignboardAnalysisResponse(
      signboardStatus: (json['signboardStatus'] as String?) ?? 'unclear',
      textDetected: json['textDetected'] as String?,
      nameOriginalScript: json['nameOriginalScript'] as String?,
      scriptVariant:
          (json['scriptVariant'] as String?)?.trim().toLowerCase() ?? 'n/a',
      languageScript:
          (json['languageScript'] as String?)?.trim().toLowerCase() ?? 'latin',
      signboardImageStatus:
          (json['signboardImageStatus'] as String?) ?? 'unclear',
      confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
    );
  }

  /// The SECOND signboard question (UC500): the tourist EDITED the name
  /// Gemini read, so the same photo is asked again - this time about the
  /// name the form is holding.
  ///
  /// Returns how well that typed name matches the name painted on the
  /// signboard. The allowances a person would make (translation, other
  /// script, a dropped "Restoran"/"Restaurant" prefix, a shortened but still
  /// distinctive form, spacing, capitalisation, small typos) count as the
  /// SAME name - the question is whether both name the same shop, not
  /// whether they spell it identically. See
  /// `LandmarkSubmissionLogic.nameMatchesSignboard` for the cutoff.
  /// Errors: A2 (timeout) - callers decide what an unanswered check means.
  Future<SignboardNameMatchResponse> verifySignboardName({
    required List<int> imageBytes,
    required String typedName,
  }) async {
    if (useLiveGemini) {
      return _verifySignboardNameLive(imageBytes, typedName);
    }

    // Stub fallback - only reached while the live call is disabled. A stub
    // cannot read a signboard, so it must NOT invent a mismatch: the check
    // stands aside and the form behaves exactly as it did before it existed.
    return const SignboardNameMatchResponse(
      matchScore: 1.0,
      matched: true,
      reason: 'stub: no live signboard check',
    );
  }

  Future<SignboardNameMatchResponse> _verifySignboardNameLive(
    List<int> imageBytes,
    String typedName,
  ) async {
    final String prompt =
        '''
  This image is a restaurant signboard photo. A tourist typed this restaurant
  name for it:

  "$typedName"

  Question: does that typed name name the SAME restaurant as the signboard in
  this photo?

  Treat as the SAME name - score them high - when they differ only by:
  - translation or romanisation of the same name, or the same name written
    in another script (Chinese/Tamil/Jawi vs Latin, and vice versa);
  - a dropped or added generic word ("Restoran", "Restaurant", "Kedai",
    "Kopitiam", "Sdn Bhd", "(M) Sdn Bhd");
  - a shortened but still distinctive form (signboard paints "Restoran
    Makanan Laut Tian Yi", typed name "Tian Yi");
  - spacing, punctuation, capitalisation, or a small typo.
  Treat as a DIFFERENT name - score them low - when the words identify a
  different restaurant, even if the typed name is itself plausible.
  "&" and "and" are different words, NEVER interchangeable: a signboard
  painted "Hup Kee & Sons" and a typed "Hup Kee and Sons" (or the reverse,
  or "&" simply dropped) is a DIFFERENT name and must score below 50 - this
  app keeps the two spellings as two separate restaurants.

  Read the signboard in ALL scripts (Malay/English, Chinese, Tamil, Jawi) -
  never answer "cannot tell" just because the signboard is not in Latin
  letters.

  Score 0-100:
  - 100 = the same name (including every allowance above);
  - 95 or more = clearly the same restaurant;
  - 40-94 = related or partly readable as the same name;
  - 0-39 = a different name, or the typed name is not on this signboard.

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "matchScore": 0-100,
    "matched": true|false,
    "reason": "one short sentence"
  }
  ''';

    final String raw = await _gemini.describeImage(
      imageBytes: imageBytes,
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'signboard-name-check',
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    // The wire score is 0-100; the app reasons in 0.0-1.0 (like every other
    // confidence it reads from Gemini).
    final double rawScore = ((json['matchScore'] as num?) ?? 0).toDouble();
    return SignboardNameMatchResponse(
      matchScore: (rawScore / 100).clamp(0.0, 1.0),
      matched: (json['matched'] as bool?) ?? rawScore >= 95,
      reason: (json['reason'] as String?) ?? '',
    );
  }

  /// The near-duplicate question (UC500): do these two photos show the same
  /// restaurant? [imageBytes] is the photo the tourist just captured,
  /// [otherImageBytes] the stored photo of a NEARBY place whose name looks
  /// like theirs (see `LandmarkSubmissionLogic.similarNearbyPlaces`).
  ///
  /// The spelling there is deliberately generous - "Ali & Abu" and "Ali and
  /// Abu" ARE the same place when the photos agree, because the photos are
  /// the evidence; the tourist still confirms before anything is merged, so
  /// nothing is decided by the model alone.
  /// Errors: A2 (timeout) - callers treat an unanswered check as "no match".
  Future<PlacePhotoMatchResponse> comparePlacePhotos({
    required List<int> imageBytes,
    required List<int> otherImageBytes,
  }) async {
    if (useLiveGemini) {
      return _comparePlacePhotosLive(imageBytes, otherImageBytes);
    }

    // Stub fallback - only reached while the live call is disabled. Nothing
    // was read, so it must never claim a match (a stub "yes" would raise the
    // merge question on every Confirm).
    return const PlacePhotoMatchResponse(
      samePlace: false,
      reason: 'stub: no photo comparison',
    );
  }

  Future<PlacePhotoMatchResponse> _comparePlacePhotosLive(
    List<int> imageBytes,
    List<int> otherImageBytes,
  ) async {
    const String prompt = '''
  Two photos are attached. The FIRST was just taken by a tourist adding this
  restaurant to the app. The SECOND is stored for a place that already
  exists nearby, under a name that looks similar to the tourist's.

  Question: do the two photos show the SAME restaurant or stall?

  - Either photo may show a signboard, a shop front, a stall, or a dish -
    judge from whatever is visible in BOTH.
  - Read any name text in either photo. The SAME name spelled differently is
    the same place ("Ali & Abu" vs "Ali and Abu"; "Restoran Ali" vs
    "Ali Restaurant"; a Chinese name and its romanised form). Different
    names on the signs mean the two photos are NOT the same place.
  - A branch of the same chain at a different spot is NOT the same place:
    weigh the shop's own look (colours, structure, signage, surroundings,
    the street/stalls around it), not just the name.
  - If the SECOND photo does not identify a place at all (a dish close-up, a
    blurry shot, an interior with no sign), answer false.

  Return ONLY raw JSON, no markdown fences, no extra text:
  {
    "samePlace": true|false,
    "confidence": 0.0-1.0,
    "reason": "one short sentence"
  }
  ''';

    final String raw = await _gemini.describeImages(
      imageBytes: <List<int>>[imageBytes, otherImageBytes],
      prompt: prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'place-photo-match',
    );
    final Map<String, dynamic> json = _decodeJsonObject(raw);
    return PlacePhotoMatchResponse(
      samePlace: (json['samePlace'] as bool?) ?? false,
      confidence: ((json['confidence'] as num?) ?? 0).toDouble().clamp(
        0.0,
        1.0,
      ),
      reason: (json['reason'] as String?) ?? '',
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
      jsonResponse: true,
      thinkingBudget: Env.geminiThinkingBudget,
      label: 'stall',
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
  static const List<String> knownMisattributions = <String>[
    'Soto Ayam',
    // Caught 2026-09-13: sold at every Malaysian pasar malam yet still the
    // Chinese original - popular here is not the same as fully merged.
    'Tau Fu Fah',
  ];

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
        '(b) ADOPTED / NATURALIZED - originated elsewhere but FULLY MERGED: '
        'Malaysia reshaped it into a local form of its own (e.g. roti '
        'canai, chee cheong fun, yong tau foo).\n'
        '(c) FOREIGN - popular in Malaysia but foreign with no distinct '
        'Malaysian identity (e.g. sushi, pizza, a Western fast-food '
        'burger).\n'
        '(d) SHARED REGIONAL - shared across Malaysia/Indonesia/etc. and '
        'genuinely part of Malaysian everyday food culture (e.g. rendang, '
        'laksa).\n\n'
        'A dish still served in its ORIGINAL foreign form, with no Malaysian '
        'evolution of its own, has NOT fully merged: it is (c), not (b) or '
        '(d), however widely it is sold in Malaysia - tau fu fah (soft tofu '
        'pudding as made in China) is (c), unlike yong tau foo which IS a '
        'Malaysian form.\n\n'
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
      label: 'origin-direct',
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
        '(b) ADOPTED / NATURALIZED in Malaysia - FULLY MERGED into a '
        'distinctly Malaysian form of its own (roti canai, yong tau foo)\n'
        '(c) FOREIGN with no distinct Malaysian identity\n'
        '(d) SHARED REGIONAL, genuinely part of Malaysian everyday food '
        'culture\n\n'
        'A dish still served in its ORIGINAL foreign form, with no Malaysian '
        'evolution of its own, has NOT fully merged: it is (c), not (b) or '
        '(d), however widely it is sold in Malaysia - tau fu fah (soft tofu '
        'pudding as made in China) is (c), unlike yong tau foo which IS a '
        'Malaysian form.\n\n'
        'Return strictly this JSON object, nothing else, no markdown fences: '
        '{"case": "a|b|c|d", "actual_origin_country": "<country>", '
        '"distinguishing_notes": "<max 2 sentences>"}';
    final String raw = await _gemini.generateText(
      prompt,
      apiKey: Env.geminiApiKeyLandmark,
      model: Env.geminiModelLandmark,
      label: 'origin-adjudicate',
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
      label: 'origin-pattern',
    );
    return _decodeJsonObject(raw);
  }
}
