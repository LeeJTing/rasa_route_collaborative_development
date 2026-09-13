import 'package:meta/meta.dart' show protected;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_recognition_result.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/origin_verification.dart';
import '../../domain_model/submitted_landmark.dart';
import '../repositories/discovery_repository_facade.dart';
import '../repositories/food_repository_facade.dart';
import 'food_name_matcher.dart';

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

  @protected
  DiscoveryRepositoryFacade createDiscoveryRepository() =>
      DiscoveryRepositoryFacade();

  @protected
  FoodRepositoryFacade createFoodRepository() => FoodRepositoryFacade();

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

  /// The minimum dish-name confidence before a genuinely-NEW detected dish
  /// may be WRITTEN to the shared `local_food` catalogue (Option C - catalogue
  /// growth from confirmed submissions). Deliberately the same high bar as
  /// [_highConfidence]: 0.6 only means "warn the tourist to verify", which is
  /// far too low to create a permanent, shared, curated row.
  static const double _catalogueInsertConfidence = 0.8;

  /// The catalogue's `food_type` values - the ONLY dish types a landmark may
  /// carry. Anything else (snacks, packaged goods, canned/bottled drinks,
  /// confectionery) is a Malaysian product at most, never an addable dish.
  static const Set<String> _catalogueFoodTypes = <String>{
    'Food',
    'Beverage',
    'Fruit',
    'Dessert',
    'Kuih',
  };

  /// Whether a recognised item fits one of the app's catalogue dish types.
  /// Returns `true` when Gemini returned no classification (blank/unknown -
  /// don't block a valid dish on a missing field), and `false` only for a
  /// PRESENT non-catalogue type ("none", "Snack", "Package", ...) - the
  /// "Malaysian product but can't be added" case.
  static bool fitsCatalogueCategory(String? foodType) {
    if (foodType == null) return true;
    final String t = foodType.trim().toLowerCase();
    if (t.isEmpty) return true;
    return _catalogueFoodTypes.any((String c) => c.toLowerCase() == t);
  }

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

  /// Restrictions the signed-in tourist holds that conflict with the
  /// recognised dish's dietary tags - e.g. a tourist who avoids "No Pork"
  /// against a dish tagged pork. Returns the USER's own restriction names
  /// (their wording, so the warning reads naturally). Tolerant, case- and
  /// substring-insensitive match: a Gemini tag like "pork" or "contains
  /// pork" still flags "No Pork". Pure - no I/O.
  static List<String> dietaryConflicts({
    required List<String> userRestrictions,
    required List<String> foodTags,
  }) {
    final Set<String> tags = foodTags
        .map(_normaliseRestriction)
        .where((String t) => t.isNotEmpty)
        .toSet();
    if (tags.isEmpty) return const <String>[];
    final List<String> conflicts = <String>[];
    for (final String restriction in userRestrictions) {
      final String needle = _normaliseRestriction(restriction);
      // Ignore empty and one/two-character noise (e.g. a stray "no").
      if (needle.length < 3) continue;
      final bool hit = tags.any(
        (String tag) =>
            tag == needle ||
            (tag.length >= 3 && tag.contains(needle)) ||
            needle.contains(tag),
      );
      if (hit) conflicts.add(restriction);
    }
    return conflicts;
  }

  static String _normaliseRestriction(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The signed-in tourist's dietary restriction names (e.g. "No Pork") - so
  /// a recognised dish that conflicts can warn on the result card. Empty when
  /// signed out or the reference query fails (best-effort: a warning must
  /// never block capture).
  Future<List<String>> userDietaryRestrictionNames() async {
    try {
      final List<DietaryRestriction> restrictions = await foodRepository
          .touristDietaryRestrictions();
      return restrictions
          .map((DietaryRestriction r) => r.name)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  /// The dietary tags to ATTRIBUTE to [food] - they ride the result's
  /// warnings AND are written onto the submitted
  /// `landmark_item.dietary_restrictions`.
  ///
  /// A FRESH observation of this very photo wins: when [observedTags] names
  /// any restrictions they describe the VARIANT actually photographed
  /// ("Cendol Jagung" may differ from the dictionary "Cendol"), so the item
  /// records its own facts. With nothing observed, a curated row's own
  /// `food_dietary_restriction` links are the authoritative fallback - the
  /// same links every other dietary feature uses. A brand-new dish (id == 0)
  /// has no links yet, so nothing is attributed when it observed nothing.
  Future<List<String>> _dietaryTagsFor(
    LocalFood food,
    List<String> observedTags,
  ) async {
    final List<String> observed = observedTags
        .map((String tag) => tag.trim())
        .where((String tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (observed.isNotEmpty) return observed;
    if (food.id == 0) return const <String>[];
    try {
      final List<DietaryRestriction> linked = await foodRepository
          .foodDietaryRestrictions(food.id);
      return linked
          .map((DietaryRestriction r) => r.name)
          .toList(growable: false);
    } catch (_) {
      // A read failure must not rob the item - the observation was empty,
      // so there is nothing to fall back to.
      return const <String>[];
    }
  }

  /// Whether the OS camera permission is granted, asking for it if not - the
  /// gate before the camera preview opens on `FoodRecognitionView` (REQ106_1).
  /// Routed through the repository so no View ever touches
  /// `permission_handler` directly.
  Future<bool> requestCameraPermission() =>
      discoveryRepository.camera.requestCameraPermission();

  late final DiscoveryRepositoryFacade discoveryRepository =
      createDiscoveryRepository();
  late final FoodRepositoryFacade foodRepository = createFoodRepository();

  /// The curated `local_food` row best matching a free-text dish name, or
  /// null when none is good enough (then Gemini's own details are used).
  /// Routed through the facade's flat `getFoods()` (never
  /// `facade.knowledge.xxx`) and [FoodNameMatcher], so "nasi lemak ayam"
  /// resolves to the curated "nasi lemak" and its authoritative details.
  Future<LocalFood?> _matchCatalogue(String name) async =>
      (await _matchCatalogueDetailed(name))?.food;

  /// [_matchCatalogue], with the TIER the match came from - an extension
  /// match ([FoodMatchTier.prefix]/[FoodMatchTier.contained]) is an unlisted
  /// VARIANT of the row and is recorded as the landmark item's variant, while
  /// a same-dish match ([FoodMatchTier.exact]/[FoodMatchTier.sameWords])
  /// records none (see [_variantFor]).
  Future<FoodNameMatch?> _matchCatalogueDetailed(String name) async {
    final List<LocalFood> catalogue = await foodRepository.getFoods();
    return FoodNameMatcher.bestMatchDetailed(name, catalogue);
  }

  /// Whether [match] means the name EXTENDS a curated dish into an unlisted
  /// variant ("cendol jagung" over "cendol") rather than being the dish
  /// itself.
  static bool _isExtensionMatch(FoodNameMatch? match) =>
      match != null &&
      (match.tier == FoodMatchTier.prefix ||
          match.tier == FoodMatchTier.contained);

  /// Like [_matchCatalogue], but ALSO tries the Gemini-reported [aliases] of
  /// the dish. The primary [name] goes through the usual tiered matcher; an
  /// alias is only trusted on an EXACT hit against one curated row's
  /// food_name or synonym (see [_exactSingleOwner]) - never a fuzzy
  /// prefix/containment match, so a loosely-translated alias cannot catch a
  /// similar-sounding dish, and an alias that several rows claim is ignored
  /// as ambiguous rather than silently picking the first row. Returns the
  /// match WITH its tier (see [FoodNameMatch]); an alias hit is always a
  /// same-dish match.
  Future<FoodNameMatch?> _matchCatalogueWithAliases(
    String name,
    List<String> aliases,
  ) async {
    final List<LocalFood> catalogue = await foodRepository.getFoods();
    final FoodNameMatch? primary = FoodNameMatcher.bestMatchDetailed(
      name,
      catalogue,
    );
    if (primary != null) return primary;
    for (final String alias in aliases) {
      final LocalFood? hit = _exactSingleOwner(alias, catalogue);
      // An alias pointing at a single curated row IS that dish (Gemini
      // merely translated the same dish's name), never an unlisted variant.
      if (hit != null) return (food: hit, tier: FoodMatchTier.exact);
    }
    return null;
  }

  /// The ONE curated row whose food_name or one of its synonyms EXACTLY
  /// equals [alias], or null when there is no such row OR the alias is
  /// ambiguous (owned by more than one row - a catalogue synonym collision
  /// such as 'Bubur Pulut Hitam' currently sitting on several rows). Only
  /// exact equality is trusted for Gemini aliases, never fuzzy matching, and
  /// the comparison folds case + Traditional/Simplified Chinese like
  /// [FoodNameMatcher.normalize].
  static LocalFood? _exactSingleOwner(String alias, List<LocalFood> catalogue) {
    final String needle = FoodNameMatcher.normalize(alias);
    if (needle.isEmpty) return null;
    LocalFood? owner;
    for (final LocalFood food in catalogue) {
      final bool hit =
          FoodNameMatcher.normalize(food.name) == needle ||
          food.synonyms.any(
            (String synonym) => FoodNameMatcher.normalize(synonym) == needle,
          );
      if (!hit) continue;
      if (owner != null) return null; // Ambiguous - more than one owner.
      owner = food;
    }
    return owner;
  }

  /// Classic Western dishes that must NEVER be offered as a landmark, no
  /// matter what the model says: they are ordinary kopitiam/mamak menu items
  /// but have no Malaysian identity of their own (see the analysis prompts'
  /// class (c) examples). A deterministic FLOOR under the model's judgement -
  /// "French Toast" kept coming back as local food and was offered as an
  /// addable landmark (user-reported). Model variance, a loose judgement or
  /// a stray catalogue row can no longer flip these.
  static const List<String> _classicForeignDishes = <String>[
    'french toast',
    'pancakes',
    'waffles',
  ];

  /// [modelSaysLocal] wins unless [dishName] is one of
  /// [_classicForeignDishes] - word-boundary containment, so "French Toast"
  /// and a decorated "French Toast Set" both trip the floor while kaya toast
  /// / roti bakar are untouched. An empty/unknown name keeps the model's
  /// judgement.
  static bool _localFoodFloor(String dishName, bool modelSaysLocal) {
    if (!modelSaysLocal) return false;
    final String needle = FoodNameMatcher.normalize(dishName);
    if (needle.isEmpty) return true;
    for (final String dish in _classicForeignDishes) {
      if (needle == dish ||
          needle.startsWith('$dish ') ||
          needle.contains(' $dish')) {
        return false;
      }
    }
    return true;
  }

  /// The `variant` to record on the submitted `landmark_item` for [food],
  /// given the name the recognition actually observed ([observedName]).
  ///
  /// A variant exists ONLY when [extension] is true - the observed name
  /// EXTENDS a curated dish without being one of its names ("cendol jagung"
  /// over "Cendol"): the item then stores dish 'Cendol' + variant 'Cendol
  /// Jagung' so the variant's own ingredients/dietary can differ from the
  /// dictionary row's.
  ///
  /// A same-dish match records NO variant, even when the spelling differs -
  /// "nasi kukus ayam goreng" is a curated synonym of row 19 and "cendol
  /// nyonya" is "Nyonya Cendol" written back-to-front: the item simply uses
  /// the curated dish.
  ///
  /// An extension that only repeats the dish's OWN names is no variant
  /// either: "Ais Kacang (ABC)" adds nothing over "Ais Kacang" while "ABC"
  /// is a curated synonym of the row, so it records NO variant (see
  /// `FoodNameMatcher.variantDistinction`) - recording it would list the
  /// same dish twice on the form.
  ///
  /// A BRAND-NEW dish (id == 0) has no dictionary row to extend - its dish
  /// name IS the observed name - except Gemini's own reported variant, which
  /// `RecognitionRepository` carries as the single synonym.
  static String _variantFor(
    LocalFood food,
    String observedName, {
    required bool extension,
  }) {
    if (extension) {
      final String observed = observedName.trim();
      if (food.id != 0 &&
          FoodNameMatcher.variantDistinction(
            food.name,
            observed,
            food.synonyms,
          ).isEmpty) {
        return '';
      }
      return observed;
    }
    if (food.id != 0) return '';
    return food.synonyms.isNotEmpty ? food.synonyms.first : '';
  }

  /// The ingredients text to record for a dish whose photo was freshly
  /// ANALYSED: the [dictionary] row's own ingredients INHERITED, plus
  /// whatever Gemini observed beyond them - so a variant ("Cendol Jagung")
  /// keeps the dictionary dish's facts AND gains what makes it that variant
  /// ("..., sweet corn"). Entries are compared trimmed + case-insensitively,
  /// the dictionary order comes first, and an observation that names nothing
  /// new leaves the dictionary text untouched. When the dictionary has
  /// nothing (a brand-new dish) the observation IS the text; when the
  /// observation has nothing the dictionary's text stands.
  static String _observedIngredients(LocalFood dictionary, String observed) {
    final String base = dictionary.ingredients.trim();
    final String seen = observed.trim();
    if (seen.isEmpty) return base;
    if (base.isEmpty) return seen;
    final List<String> merged = <String>[];
    final Set<String> seenKeys = <String>{};
    for (final String ingredient in <String>[
      ...base.split(','),
      ...seen.split(','),
    ]) {
      final String name = ingredient.trim();
      if (name.isEmpty || !seenKeys.add(name.toLowerCase())) continue;
      merged.add(name);
    }
    return merged.join(', ');
  }

  /// Gemini's full analysis is authoritative on WHICH dish a photo shows, but
  /// it must never overwrite an existing `local_food` record: if [fromGemini]
  /// is already curated, the stored row - its authoritative details AND its
  /// id (so a submitted `landmark_item` links to it instead of arriving
  /// unlinked with `local_food_id = 0`) - wins over the freshly-generated
  /// copy. Returns [fromGemini] itself only when there is no curated match.
  /// A Gemini-reported [LocalFood.aliases] alias pointing at a single curated
  /// row is treated as that match too (see [_matchCatalogueWithAliases]), so
  /// "bubur ca ca" with the alias "Bubur Cha Cha" resolves to the curated
  /// row instead of creating a duplicate.
  ///
  /// Returns the food AND whether the match was an EXTENSION - an unlisted
  /// variant of the row - which decides the item's variant text (see
  /// [_variantFor]).
  Future<({LocalFood food, bool isExtension})> _preferCuratedOverGemini(
    LocalFood fromGemini,
  ) async {
    final FoodNameMatch? match = await _matchCatalogueWithAliases(
      fromGemini.name,
      fromGemini.aliases,
    );
    if (match == null) return (food: fromGemini, isExtension: false);
    return (food: match.food, isExtension: _isExtensionMatch(match));
  }

  /// Recognises the food in [imageBytes] (REQ106_2, UC500 two-phase flow):
  ///  1. A quick, name-only Gemini call (`RecognitionRepository.identifyFoodName`).
  ///  2. If that name (or a whole-word variant of it - "nasi lemak ayam"
  ///     resolving to the curated "nasi lemak") is already in the catalogue,
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
      // The full analysis decides WHICH dish this is - but if that dish is
      // already curated, the stored row (data + id) wins over Gemini's copy.
      final ({LocalFood food, bool isExtension}) curated =
          await _preferCuratedOverGemini(analysis.food);
      final LocalFood food = curated.food;
      // Hybrid storage: the dictionary row keeps its canonical fields,
      // while the ITEM records the variant's own observed facts - the
      // observed ingredients whenever the analysis named any.
      final LocalFood itemFood = food.id == 0
          ? food
          : food.copyWith(
              ingredients: _observedIngredients(
                food,
                analysis.food.ingredients,
              ),
            );
      // Observed dietary tags when the analysis saw any (the variant's own
      // restrictions), else the curated row's authoritative links.
      final List<String> dietaryRestrictions = await _dietaryTagsFor(
        itemFood,
        analysis.dietaryRestrictions,
      );
      return FoodRecognitionResult(
        isLocalFood: _localFoodFloor(food.name, analysis.isLocal),
        fitsCatalogueCategory: fitsCatalogueCategory(analysis.foodType),
        candidates: <LocalFood>[itemFood],
        variant: _variantFor(
          food,
          analysis.food.name,
          extension: curated.isExtension,
        ),
        priceMin: analysis.priceMin,
        priceMax: analysis.priceMax,
        confidence: analysis.confidence,
        localFoodConfidence: analysis.localConfidence,
        imageQuality: analysis.imageQuality,
        imageQualityIssues: analysis.imageQualityIssues,
        dietaryRestrictions: dietaryRestrictions,
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
      final LocalFood? match = await _matchCatalogue(candidate.dish);
      final LocalFood food =
          match ?? _nameOnlyFood(candidate.dish, quick.foodCategory);
      if (!candidates.any((LocalFood f) => f.name == food.name)) {
        candidates.add(food);
      }
    }

    final List<LocalFood> result;
    // Gemini's suggested range from the QUICK call rides every path where
    // the full analysis does NOT run (the catalogue fast path and the
    // candidate list) - the quick prompt asks for it too, so a dish settled
    // without the deeper call still carries a range for the form's price
    // warning. The full analysis overrides it with its own range when it
    // does run.
    double priceMin = quick.priceMin;
    double priceMax = quick.priceMax;
    // Confidence of whatever produced the single result - the quick call for
    // a catalogue hit, the full analysis otherwise. Low values are surfaced
    // in the UI so a shaky result is never presented as certain.
    double confidence = quick.confidence;
    double localFoodConfidence = quick.localFoodConfidence;
    String imageQuality = quick.imageQuality;
    List<String> imageQualityIssues = quick.imageQualityIssues;
    List<String> dietaryRestrictions = const <String>[];
    // The single result's VARIANT name - the observed/recognised name when
    // it EXTENDS the dictionary dish into an unlisted variant (see
    // [_variantFor]). Empty for a multi-candidate outcome (the picked
    // candidate resolves separately) and for same-dish matches.
    String variant = '';
    // The catalogue dish-type classification - refreshed to the full
    // analysis when one runs (it is the authoritative call).
    String foodType = quick.foodType;
    if (candidates.length > 1) {
      result = candidates.take(3).toList(growable: false);
    } else {
      // "Confident" single result. The cheap catalogue-match path is only
      // trusted when the quick call is HIGHLY confident AND the photo itself
      // was usable - a shaky name, or a name read off a blurry/dark photo,
      // must never be matched to a catalogue record and shown as certain.
      // Anything less is re-judged by the full analysis, which is the
      // deeper, authoritative call.
      final FoodNameMatch? quickMatch = await _matchCatalogueDetailed(
        quick.dish,
      );
      final LocalFood? existing = quickMatch?.food;
      if (existing != null &&
          quick.confidence >= _highConfidence &&
          !isPoorImageQuality(quick.imageQuality)) {
        result = <LocalFood>[existing];
        // The fast path skips the full analysis: the only observation is the
        // quick call's own name - recorded as the variant when it EXTENDS
        // the dictionary dish, never when it simply IS the dish.
        variant = _variantFor(
          existing,
          quick.dish,
          extension: _isExtensionMatch(quickMatch),
        );
        // No fresh observation => the dish's tags are read from the curated
        // row's own `food_dietary_restriction` links - otherwise a
        // catalogue dish would never warn at all here.
        dietaryRestrictions = await _dietaryTagsFor(existing, const <String>[]);
      } else {
        final analysis = await discoveryRepository.recognition.analyzeFoodFull(
          imageBytes,
        );
        // Same rule as the not-local branch: an existing curated row always
        // beats Gemini's fresh copy - never overwrite `local_food` data.
        // The ITEM then records the variant's own observed ingredients.
        final ({LocalFood food, bool isExtension}) curated =
            await _preferCuratedOverGemini(analysis.food);
        final LocalFood food = curated.food;
        result = <LocalFood>[
          food.id == 0
              ? food
              : food.copyWith(
                  ingredients: _observedIngredients(
                    food,
                    analysis.food.ingredients,
                  ),
                ),
        ];
        variant = _variantFor(
          food,
          analysis.food.name,
          extension: curated.isExtension,
        );
        priceMin = analysis.priceMin;
        priceMax = analysis.priceMax;
        confidence = analysis.confidence;
        localFoodConfidence = analysis.localConfidence;
        imageQuality = analysis.imageQuality;
        imageQualityIssues = analysis.imageQualityIssues;
        // The analysis observed this photo, so its tags ride the item; the
        // dictionary row's links only step in when it observed none.
        dietaryRestrictions = await _dietaryTagsFor(
          result.first,
          analysis.dietaryRestrictions,
        );
        foodType = analysis.foodType;
      }
    }

    return FoodRecognitionResult(
      // The classic-foreign floor still applies: "French Toast" matching a
      // catalogue row must never become addable as local food.
      isLocalFood: _localFoodFloor(
        result.isEmpty ? '' : result.first.name,
        true,
      ),
      fitsCatalogueCategory: fitsCatalogueCategory(foodType),
      candidates: result,
      // The single result's variant (empty for a picker outcome / a
      // same-dish match) - carried onto the submitted `landmark_item`.
      variant: variant,
      priceMin: priceMin,
      priceMax: priceMax,
      confidence: confidence,
      localFoodConfidence: localFoodConfidence,
      imageQuality: imageQuality,
      imageQualityIssues: imageQualityIssues,
      dietaryRestrictions: dietaryRestrictions,
    );
  }

  /// Manual fallback when Gemini's candidates don't include the right dish
  /// (the "type the food name" escape hatch on the result popup). VERIFIES the
  /// typed [name] against the photo - the user may be wrong, and a typed name
  /// must never be accepted on the user's say-so alone.
  ///
  /// Always sends the typed name AND the captured image to Gemini
  /// (`RecognitionRepository.analyzeFoodByName`) to check the claim first
  /// (decision: "always verify", not a catalogue fast-path). The curated
  /// catalogue row is preferred for the typed dish's details whenever one
  /// exists (Gemini must never overwrite existing `local_food` data) - but
  /// only after verification. When the photo does NOT show the typed name,
  /// what Gemini actually saw ([..observedFood]) comes back so the UI can
  /// warn instead of silently accepting a mismatched landmark; if the tourist
  /// then confirms the typed name anyway, the curated row (with its id) is
  /// what gets carried, never Gemini's copy.
  Future<
    ({
      LocalFood food,
      String variant,
      double priceMin,
      double priceMax,
      bool nameMatchesPhoto,
      double matchConfidence,
      bool isLocalFood,
      bool fitsCatalogueCategory,
      String observedFood,
      List<String> dietaryRestrictions,
    })
  >
  resolveByName(List<int> imageBytes, String name) async {
    final String trimmed = name.trim();
    final analysis = await discoveryRepository.recognition.analyzeFoodByName(
      imageBytes,
      trimmed,
    );
    LocalFood food = analysis.food;
    String variant = '';
    double priceMin = analysis.priceMin;
    double priceMax = analysis.priceMax;
    bool isLocalFood = analysis.isLocal;
    List<String> dietaryRestrictions = analysis.dietaryRestrictions;
    bool fits = fitsCatalogueCategory(analysis.foodType);
    // The catalogue lookup is a details optimisation, never a substitute for
    // checking the photo - it fills in the (more reliable) curated details
    // for the typed dish whenever one exists, whether or not the photo
    // matched. A mismatch still warns via [observedFood]; if the tourist
    // confirms the typed name anyway, the carried food is the curated row -
    // never Gemini's overwrite of it - and its id is what links the eventual
    // `landmark_item` to the existing `local_food`. Gemini aliases are only
    // trusted when the photo really shows the typed name - on a MISMATCH they
    // describe the OBSERVED dish, which must never relabel what the tourist
    // typed (see the mismatch branch below).
    final FoodNameMatch? match = await _matchCatalogueWithAliases(
      trimmed,
      analysis.nameMatchesPhoto ? analysis.food.aliases : const <String>[],
    );
    if (match != null) {
      // The item records the variant the tourist typed/confirmed ONLY when
      // it EXTENDS the dictionary dish ("Cendol Jagung" -> "Cendol") - a
      // synonym or a word-order spelling of the dish itself records none.
      // The observed ingredients only ride along when the photo really
      // showed the typed dish - a mismatch confirmation carries the
      // dictionary row untouched.
      variant = _variantFor(
        match.food,
        trimmed,
        extension: _isExtensionMatch(match),
      );
      food = analysis.nameMatchesPhoto
          ? match.food.copyWith(
              ingredients: _observedIngredients(
                match.food,
                analysis.food.ingredients,
              ),
            )
          : match.food;
      // Gemini's suggested range from the VERIFICATION describes the typed
      // dish as it is sold - keep it, so the form can show it under the
      // price field. On a mismatch the reply describes the OBSERVED dish
      // instead, so nothing rides along there.
      priceMin = analysis.nameMatchesPhoto ? analysis.priceMin : 0;
      priceMax = analysis.nameMatchesPhoto ? analysis.priceMax : 0;
      // A curated row IS Malaysian local food and a valid catalogue dish
      // type by definition - the observed photo's localness/category is
      // irrelevant once the tourist commits to a curated dish.
      isLocalFood = true;
      fits = true;
      // Observed tags only when the photo really showed the typed dish;
      // otherwise the curated row's own links.
      dietaryRestrictions = await _dietaryTagsFor(
        food,
        analysis.nameMatchesPhoto
            ? analysis.dietaryRestrictions
            : const <String>[],
      );
    } else if (!analysis.nameMatchesPhoto) {
      // Gemini could not verify the typed name AND there is no curated row
      // for it. Its response describes the dish it actually SAW (the
      // observed food) - carrying that as the typed dish would put one
      // dish's name on another dish's details (a "Char Siew" name riding on
      // a Ramly burger's details). Carry a name-only entry for exactly what
      // the tourist typed instead: if they confirm it anyway, that is the
      // dish that gets added, with no borrowed details.
      food = _nameOnlyFood(trimmed, '');
      priceMin = 0;
      priceMax = 0;
      dietaryRestrictions = const <String>[];
    }
    return (
      food: food,
      variant: variant,
      priceMin: priceMin,
      priceMax: priceMax,
      nameMatchesPhoto: analysis.nameMatchesPhoto,
      matchConfidence: analysis.matchConfidence,
      // The classic-foreign floor holds here too - a typed Western dish
      // cannot become local by being verified.
      isLocalFood: _localFoodFloor(food.name, isLocalFood),
      fitsCatalogueCategory: fits,
      observedFood: analysis.observedFood,
      dietaryRestrictions: dietaryRestrictions,
    );
  }

  /// Enriches a candidate the tourist picked from the top-3 picker (A5).
  /// These candidates came FROM the photo, so no name-vs-photo verification
  /// is needed - this just fills in full details: the catalogue row if there
  /// is one, else a Gemini name+image analysis of the picked dish.
  Future<
    ({
      LocalFood food,
      String variant,
      double priceMin,
      double priceMax,
      bool fitsCatalogueCategory,
      List<String> dietaryRestrictions,
    })
  >
  enrichCandidate(List<int> imageBytes, String name) async {
    final String trimmed = name.trim();
    final FoodNameMatch? match = await _matchCatalogueDetailed(trimmed);
    if (match != null) {
      return (
        food: match.food,
        variant: _variantFor(
          match.food,
          trimmed,
          extension: _isExtensionMatch(match),
        ),
        priceMin: 0.0,
        priceMax: 0.0,
        fitsCatalogueCategory: true,
        // Curated row => its own links are the authoritative tags (Gemini's
        // are ignored - see [_dietaryTagsFor]).
        dietaryRestrictions: await _dietaryTagsFor(
          match.food,
          const <String>[],
        ),
      );
    }
    final analysis = await discoveryRepository.recognition.analyzeFoodByName(
      imageBytes,
      trimmed,
    );
    // No curated row matched the picked name - but Gemini's aliases may point
    // at one exactly (e.g. picking "bubur ca ca" whose alias "Bubur Cha Cha"
    // is curated), which keeps the picker linked instead of creating a
    // duplicate.
    final FoodNameMatch? curated = analysis.food.aliases.isEmpty
        ? null
        : await _matchCatalogueWithAliases(
            analysis.food.name,
            analysis.food.aliases,
          );
    // The analysis observed this photo: when it resolves to a curated row,
    // the item keeps the observed ingredients (the variant's own facts) and
    // the variant name when the observed name EXTENDS the dictionary dish.
    final LocalFood resolved = curated == null
        ? analysis.food
        : curated.food.copyWith(
            ingredients: _observedIngredients(
              curated.food,
              analysis.food.ingredients,
            ),
          );
    return (
      food: resolved,
      variant: _variantFor(
        curated?.food ?? analysis.food,
        analysis.food.name,
        extension: _isExtensionMatch(curated),
      ),
      // Gemini analysed this photo of the picked dish, so its suggested
      // range applies whether or not it resolved to a curated row.
      priceMin: analysis.priceMin,
      priceMax: analysis.priceMax,
      fitsCatalogueCategory: curated != null
          ? true
          : fitsCatalogueCategory(analysis.foodType),
      // The observation's tags ride the item when it resolved to a curated
      // row; an unmatched dish simply keeps them.
      dietaryRestrictions: curated != null
          ? await _dietaryTagsFor(resolved, analysis.dietaryRestrictions)
          : analysis.dietaryRestrictions,
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

  /// Option C - grow the `local_food` catalogue from confirmed submissions.
  ///
  /// Every food on a submitted landmark is a candidate, but only a genuinely
  /// NEW, HIGH-CONFIDENCE Malaysian local food is written:
  ///   * not test/QA data (`isFake`);
  ///   * not already a curated row (`id != 0`);
  ///   * judged Malaysian local food ([FoodSubmission.isLocalFood]);
  ///   * dish-name confidence at least [_catalogueInsertConfidence] - the
  ///     same bar the app uses before trusting a quick recognition enough to
  ///     shortcut to a curated record (0.6 is only "warn the tourist");
  ///   * the matcher finds NO existing canonical entry (exact / same words
  ///     reordered / whole-word prefix / containment) - so "nasi lemak ayam"
  ///     never becomes a new row when "nasi lemak" already exists; it just
  ///     uses the canonical one.
  ///
  /// Best-effort: the caller has already saved the landmark, so a catalogue
  /// write failure must not fail the submission.

  /// PRE-SUBMIT gate: every food being added that is NOT a direct catalogue
  /// link (`id == 0`, not fake) must pass the 3-step origin verification
  /// BEFORE the landmark is saved. If any fails, this throws
  /// [LandmarkVerificationRejectedException] and the caller must not save the
  /// landmark - a non-Malaysian dish must never become a landmark at all, not
  /// merely be kept out of the catalogue.
  ///
  /// Catalogue-linked foods (`id != 0`) skip the gate - they were already
  /// vetted when they entered the curated list.
  Future<void> verifyNewFoodsOrThrow(List<FoodSubmission> foods) async {
    for (final FoodSubmission entry in foods) {
      if (entry.isFake) continue;
      final LocalFood food = entry.food;
      if (food.id != 0) continue; // Already a curated row - direct link.
      final OriginVerification verification = await discoveryRepository
          .verifyDishOrigin(food.name);
      if (verification.verdict != OriginVerdict.accept) {
        throw LandmarkVerificationRejectedException(
          '"${food.name}" has not fully merged into Malaysian local food, '
          'so it cannot be added as a new landmark.',
        );
      }
    }
  }

  /// Returns the dishes actually written, keyed by the dish name the caller
  /// wrote onto `landmark_item.dish` (the recognized `food.name` verbatim), so
  /// the submit flow can backfill those items' `local_food_id` now that the
  /// new rows exist.
  ///
  /// [alreadyVerified] - set true when the caller ran [verifyNewFoodsOrThrow]
  /// first (the submit flow does), so the 3-step gate is not paid for twice.
  Future<Map<String, int>> registerNewDishes(
    List<FoodSubmission> foods, {
    bool alreadyVerified = false,
  }) async {
    final List<LocalFood> catalogue = await foodRepository.getFoods();
    // Working copy, so a dish written earlier in this loop is seen by the
    // matcher for the ones after it (dedupe within one submission).
    final List<LocalFood> working = List<LocalFood>.of(catalogue);
    // Reference lookups fetched ONCE, so normalising the association links
    // for every new dish does not re-query `food_preference` /
    // `dietary_restriction` per dish.
    final ({Map<String, int> tastes, Map<String, int> categories})
    preferenceLookup = await foodRepository.preferenceIdLookup();
    final Map<String, int> restrictionIdByName = <String, int>{
      for (final DietaryRestriction restriction
          in await foodRepository.dietaryRestrictions())
        restriction.name.trim().toLowerCase(): restriction.id,
    };

    final Map<String, int> inserted = <String, int>{};
    for (final FoodSubmission entry in foods) {
      if (entry.isFake) continue;
      final LocalFood food = entry.food;
      if (food.id != 0) continue;
      if (!entry.isLocalFood) continue;
      if (entry.confidence < _catalogueInsertConfidence) continue;
      if (FoodNameMatcher.bestMatch(food.name, working) != null) continue;

      // 3-step origin verification - a single self-scored Gemini answer is
      // exactly what let Soto Ayam through, so a brand-new dish must pass
      // three SEPARATELY-framed checks before it may be written to the
      // shared, curated catalogue. A check counts as Malaysian for (a) origin,
      // (b) adopted/naturalized or (d) shared regional; at least 2 of 3 must
      // agree (accept). Anything less is NOT inserted. Skipped entirely when
      // the submit flow already ran [verifyNewFoodsOrThrow] first.
      if (!alreadyVerified) {
        final OriginVerification verification = await discoveryRepository
            .verifyDishOrigin(food.name);
        if (verification.verdict != OriginVerdict.accept) continue;
      }

      final LocalFood? saved = await foodRepository.insertFood(
        // Gemini's aliases are the row's alternate names: they are genuine
        // other names/spellings of the SAME dish, which is exactly what
        // `local_food.synonyms` holds for curated rows (and what the matcher
        // reads back on future recognitions). The transient variant stays
        // where it is when Gemini supplied no aliases.
        food.aliases.isEmpty ? food : food.copyWith(synonyms: food.aliases),
      );
      if (saved != null) {
        working.add(saved);
        inserted[food.name] = saved.id;
        // The tourist's own photo of the dish becomes the catalogue row's
        // photo, so a new dish is never listed without an image.
        await _attachDishPhoto(saved.id, entry);
        await _linkAssociations(
          saved.id,
          entry,
          preferenceLookup,
          restrictionIdByName,
        );
      }
    }
    return inserted;
  }

  /// Attaches the submitted dish photo to a brand-new catalogue row
  /// (`local_food_image`), so the dish does not sit in the catalogue with no
  /// image. The photo was already uploaded for the landmark item
  /// (`landmark-images` bucket) - its public URL is stored as-is and resolves
  /// correctly (`APIManager.resolveImageUrl` passes full URLs through). A
  /// food without a photo (e.g. a name-typed dish) simply gets none.
  /// Best-effort: the landmark is already saved, so a failed photo link must
  /// never fail the submission.
  Future<void> _attachDishPhoto(int localFoodId, FoodSubmission entry) async {
    final String? imageUrl = entry.imageUrl;
    if (imageUrl == null || imageUrl.trim().isEmpty) return;
    try {
      await foodRepository.addFoodImage(
        localFoodId: localFoodId,
        imageName: imageUrl,
      );
    } catch (_) {
      // Ignored - see doc above.
    }
  }

  /// Writes the `local_food_preference` (tastes + category) and
  /// `food_dietary_restriction` links for a freshly-inserted dish, matching
  /// the scraper's link shapes. Names are normalised against the canonical
  /// reference rows (unknown names are skipped); duplicates are dropped by
  /// the repository. Best-effort per link - a failed link never fails the
  /// insert that already succeeded.
  Future<void> _linkAssociations(
    int localFoodId,
    FoodSubmission entry,
    ({Map<String, int> tastes, Map<String, int> categories}) preferenceLookup,
    Map<String, int> restrictionIdByName,
  ) async {
    final LocalFood food = entry.food;
    final List<int> tasteIds = <int>[
      for (final String taste in food.tastes)
        if (preferenceLookup.tastes[taste.trim().toLowerCase()]
            case final int id)
          id,
    ];
    final int mainTasteId =
        preferenceLookup.tastes[food.mainTaste.trim().toLowerCase()] ?? 0;
    final int? categoryId =
        preferenceLookup.categories[food.category.trim().toLowerCase()];
    await foodRepository.linkFoodPreferences(
      localFoodId,
      tasteIds: tasteIds,
      mainTasteId: mainTasteId,
      categoryId: categoryId,
    );

    final List<int> restrictionIds = <int>[
      for (final String name in entry.dietaryRestrictions)
        if (restrictionIdByName[name.trim().toLowerCase()] case final int id)
          id,
    ];
    await foodRepository.linkFoodDietaryRestrictions(
      localFoodId,
      restrictionIds,
    );
  }
}

/// Thrown by [FoodRecognitionLogic.verifyNewFoodsOrThrow] when a dish that is
/// NOT already in the catalogue fails the 3-step origin verification - the
/// landmark must not be saved. `toString` returns the message cleanly so a
/// ViewModel can surface it directly.
class LandmarkVerificationRejectedException implements Exception {
  LandmarkVerificationRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}
