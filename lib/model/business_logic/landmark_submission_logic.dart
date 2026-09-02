import 'dart:math' as math;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/landmark_report_reason.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/landmark_repository_facade.dart';
import 'location_rules.dart';

/// Submitting a new food landmark and attaching dishes to it.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class LandmarkSubmissionLogic {
  LandmarkSubmissionLogic();

  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();

  /// Restaurant signboard photo (BF-16..21). Extracts the restaurant name
  /// and verifies the whole signboard is in frame - throws on either
  /// failure, matching `FoodRecognitionLogic.recognizeFood`'s pattern for
  /// its own A3/A4/A18 checks (this used to live in
  /// `FoodRecognitionViewModel.captureSignboard` instead, inspecting the
  /// raw `SignboardAnalysisResponse` directly in the ViewModel - a domain
  /// invariant about what counts as a valid capture, not a form-UX check,
  /// so it belongs here, not there).
  ///
  /// For non-Latin signboards (Chinese/Tamil/Jawi) the returned name is the
  /// exact signboard text with the romanised translation in parentheses,
  /// e.g. "海天楼 (Hai Tian Lou)" - see [displaySignboardName]. The tourist
  /// can edit the field afterwards.
  /// Errors: A2 (timeout), A7 (no text), A19 (incomplete frame)
  Future<String> analyzeSignboard(List<int> imageBytes) async {
    final response = await repository.recognition.analyzeSignboard(imageBytes);
    if (response.signboardImageStatus != 'complete') {
      throw Exception(
        'Signboard not fully in frame. Please ensure the entire signboard is visible.',
      );
    }
    if (response.textDetected == null || response.textDetected!.isEmpty) {
      throw Exception('Unable to extract restaurant name from signboard.');
    }
    final String romanised = sanitiseSignboardName(response.textDetected!);
    if (romanised.isEmpty) {
      // The only "text" was noise (e.g. a lone phone number) - nothing to
      // auto-fill, same A7 outcome as finding no text at all.
      throw Exception('Unable to extract restaurant name from signboard.');
    }
    return displaySignboardName(
      romanised: romanised,
      originalScript: response.nameOriginalScript,
      languageScript: response.languageScript,
    );
  }

  /// Strips non-name noise Gemini sometimes appends to a signboard name:
  /// lot numbers, addresses, phone numbers and postcodes (Malaysian signs
  /// carry "Lot 12, Jalan ...", "Tel: 012-345 6789" under the name). This is
  /// a deterministic safety net UNDER the signboard prompt - the prompt asks
  /// for the name alone, but the model occasionally includes a stray lot or
  /// phone number; that must never land in the Restaurant Name field.
  /// Returns the cleaned name, which may be empty if the raw text was only
  /// noise (callers should treat that as "no text extracted").
  static String sanitiseSignboardName(String raw) {
    // Treat each line of a multi-line signboard as its own segment, then
    // also split on commas/semicolons, so "Restoran ABC\nLot 12" becomes
    // two independent parts and the noise can be dropped without touching
    // the name.
    final String flat = raw.trim().replaceAll(RegExp(r'[\r\n]+'), ', ');
    final Iterable<String> segments = flat
        .split(RegExp(r'\s*[,;]\s*'))
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty);

    String result = segments
        .where((String segment) => !_isSignboardNoise(segment))
        .join(', ');

    // A phone number glued to the name without a separator
    // ("Restoran ABC Tel: 012-345 6789") - strip it inline.
    result = result.replaceAll(
      RegExp(
        r'\s*(?:tel|phone|hp|whatsapp|contact|fax)\s*[:.\-]?\s*'
        r'\+?\d{1,3}(?:[ -]?\d{2,4}){2,}',
        caseSensitive: false,
      ),
      ' ',
    );

    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result.replaceAll(RegExp(r'^[,.;:\- ]+|[,\s.;:\-]+$'), '').trim();
  }

  /// Builds the Restaurant Name value shown for a signboard capture:
  /// - Latin-script signs (or when the original-script name is missing or
  ///   identical to the romanised form) return just the romanised name;
  /// - non-Latin signs return the exact signboard text with the romanised
  ///   translation in parentheses, e.g. "海天楼 (Hai Tian Lou)", so the
  ///   signboard text is kept alongside the translated form.
  static String displaySignboardName({
    required String romanised,
    String? originalScript,
    String languageScript = 'latin',
  }) {
    final String? original = originalScript == null
        ? null
        : sanitiseSignboardName(originalScript);
    final bool showBoth =
        original != null &&
        original.isNotEmpty &&
        original != romanised &&
        languageScript != 'latin';
    return showBoth ? '$original ($romanised)' : romanised;
  }

  /// True when [segment] is signboard noise (address/phone/postcode/lot),
  /// not part of the restaurant name. Conservative - a segment is only
  /// treated as noise when it clearly matches one of those patterns.
  static bool _isSignboardNoise(String segment) {
    final String s = segment.trim().toLowerCase();
    if (s.isEmpty) return true;

    // A phone number, optionally preceded by "Tel:" / "HP:" / "Fax:" etc.
    final String maybePhone = s.replaceFirst(
      RegExp(r'^(?:tel|phone|hp|whatsapp|contact|fax)\s*[:.\-]?\s*'),
      '',
    );
    if (RegExp(r'^\+?\d[\d\s().-]{6,}$').hasMatch(maybePhone)) return true;

    // Lot / unit / block references: "lot 12", "lot no. 12", "unit 3a".
    if (RegExp(r'^(?:lot|unit|blok|block)\b').hasMatch(s)) return true;

    // A standalone "No. 12" (address unit number, not a name like
    // "No. 1 Noodle Bar" - that has more words so won't match this).
    if (RegExp(r'^no\.?\s*\d+$').hasMatch(s)) return true;

    // A Malaysian postcode, with or without a following town name.
    if (RegExp(r'^\d{5}\b').hasMatch(s)) return true;

    // Address lines / town names.
    return RegExp(
      r'^(?:jalan|jln\.?|lorong|lebuh|persiaran|taman|kuala lumpur|'
      r'petaling jaya|subang jaya|shah alam|klang|selangor|ampang)\b',
    ).hasMatch(s);
  }

  /// Stall photo (A17). Verifies the whole stall is in frame - does NOT
  /// auto-fill anything. Throws on failure - see [analyzeSignboard]'s doc
  /// for why this validation lives here now, not in the ViewModel.
  /// Errors: A2 (timeout), A8 (not detected), A15 (incomplete frame)
  Future<void> analyzeStall(List<int> imageBytes) async {
    final response = await repository.recognition.analyzeStall(imageBytes);
    if (response.stallStatus != 'detected') {
      throw Exception(
        'Unable to verify this is a food stall. Please capture the stall image.',
      );
    }
    if (response.stallImageStatus != 'complete') {
      throw Exception(
        'Stall not fully in frame. Please ensure the entire stall is visible.',
      );
    }
  }

  /// Checks whether a restaurant with this name already exists (A13).
  /// Case-insensitive; returns null when nothing matches.
  Future<Restaurant?> checkRestaurantExists(String name) =>
      repository.restaurant.findByName(name);

  /// The signed-in tourist's id, for `LandmarkItem.touristId`. Null if
  /// nobody is signed in / the session can't be resolved yet.
  Future<String?> currentTouristId() => repository.auth.currentTouristId();

  /// One submitted landmark (with its dishes and opening hours) for the
  /// detail screen - flat passthrough to the repository. Null when the id
  /// matches nothing.
  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) =>
      repository.landmark.getSubmittedLandmarkById(landmarkId);

  /// Every submitted landmark [touristId] has contributed dishes to, newest
  /// first - flat passthrough to the repository (see the repository doc for
  /// why the contributor lives on `landmark_item`, not `submitted_landmark`).
  Future<List<SubmittedLandmark>> getSubmittedLandmarksByTourist(
    String touristId,
  ) => repository.landmark.getSubmittedLandmarksByTourist(touristId);

  /// Uploads a captured photo - a food's photo, or the landmark's
  /// signboard/stall photo - to Supabase Storage and returns what the row
  /// stores: the object name (`image_id`) and its public URL (`image_url`).
  /// The actual upload lives in the repository - this method just makes it
  /// reachable from the ViewModel through the one facade this class holds.
  Future<({String id, String url})> uploadImage(List<int> bytes) =>
      repository.landmark.uploadImage(bytes);

  /// Day names for validation messages.
  static const Map<Weekday, String> _dayNames = <Weekday, String>{
    Weekday.monday: 'Monday',
    Weekday.tuesday: 'Tuesday',
    Weekday.wednesday: 'Wednesday',
    Weekday.thursday: 'Thursday',
    Weekday.friday: 'Friday',
    Weekday.saturday: 'Saturday',
    Weekday.sunday: 'Sunday',
  };

  /// Whether [opensAt]/[closesAt] (minutes since midnight) form a valid
  /// single range - closing strictly after opening. The same rule
  /// [validateOperatingHours] checks across a whole day's rows, exposed here
  /// separately so a single in-progress edit (e.g.
  /// `AddLandmarkViewModel.setRangeTime`, which rejects a pick that would
  /// make a range invalid, keeping the previous value) can check just one
  /// range without needing a whole day's rows to check overlap against.
  bool isValidTimeOrder(int opensAt, int closesAt) => closesAt > opensAt;

  /// Validates the two operating-hours rules that are domain invariants -
  /// true of an `OpeningHour` no matter where the data came from, unlike a
  /// completeness check ("did the tourist fill in both times"), which stays
  /// in `AddLandmarkViewModel` since it's only meaningful because a human is
  /// mid-way through filling in a form (BF-19..23):
  ///  - closing time must be strictly after opening time - no overnight
  ///    wrap-around, since "24:00" already exists to express "open until
  ///    midnight" without needing to cross into the next day;
  ///  - multiple rows for the same day must not overlap (e.g.
  ///    "12:00-15:00" and "14:00-18:00" on the same day is invalid).
  ///
  /// Only meaningful for rows that have already passed the ViewModel's own
  /// completeness check (every Open row's `opensAt`/`closesAt` non-null) -
  /// assumes that rather than re-checking it, since completeness isn't this
  /// method's concern.
  String? validateOperatingHours(
    Map<Weekday, List<OpeningHour>> operatingHours,
  ) {
    for (final MapEntry<Weekday, List<OpeningHour>> entry
        in operatingHours.entries) {
      final String dayName = _dayNames[entry.key]!;
      final List<OpeningHour> openRows = entry.value
          .where((OpeningHour hour) => hour.status == DayStatus.open)
          .toList();
      if (openRows.isEmpty) continue;

      final List<(int, int)> ranges = <(int, int)>[];
      for (final OpeningHour row in openRows) {
        if (!isValidTimeOrder(row.opensAt!, row.closesAt!)) {
          return 'Closing time must be after opening time for $dayName.';
        }
        ranges.add((row.opensAt!, row.closesAt!));
      }

      ranges.sort((a, b) => a.$1.compareTo(b.$1));
      for (int i = 1; i < ranges.length; i++) {
        if (ranges[i].$1 < ranges[i - 1].$2) {
          return "$dayName's operating hours overlap - please adjust the times.";
        }
      }
    }
    return null;
  }

  /// Whether [price] (MYR) is a valid price for a landmark's food item
  /// (A16) - a domain invariant true of any price regardless of where it
  /// came from (this form, a bulk import, an admin tool), not a form-UX
  /// check. Used to live duplicated three times inside
  /// `AddLandmarkViewModel` (`setPrimaryFoodPrice`, `setAdditionalFoodPrice`,
  /// and again inline in `submitLandmark`) - centralised here instead.
  bool isValidPrice(double price) => price > 0 && price <= 1000;

  /// Soft, non-blocking price guidance: when Gemini supplied a suggested
  /// selling range for the recognised dish (both [priceMin]/[priceMax] > 0),
  /// returns a user-facing warning when [price] falls outside it - so an
  /// accidental typo (e.g. 500 instead of 5) is caught at the field, not at
  /// submit. Returns null when the price is inside the range, or no
  /// suggestion is known. A warning only - the tourist can still enter any
  /// valid price.
  String? suggestedPriceWarning(
    String foodName,
    double price,
    double priceMin,
    double priceMax,
  ) {
    if (priceMin <= 0 || priceMax < priceMin) return null;
    if (price < priceMin || price > priceMax) {
      return 'Suggested price for $foodName is '
          'RM ${priceMin.toStringAsFixed(2)} - RM ${priceMax.toStringAsFixed(2)}. '
          'Double-check your price.';
    }
    return null;
  }

  /// Haversine distance between two coordinates, in metres - a pure
  /// geometric calculation, true regardless of where the coordinates came
  /// from.
  static double _distanceMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusMetres = 6371000;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMetres * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180);

  /// Whether a tourist-adjusted pin at ([adjustedLat], [adjustedLon]) is
  /// still within the allowed correction range of [current] (A9.1) - the
  /// pin can be moved at most 100m from the GPS fix. Always allowed if
  /// [current] itself has no fix yet - nothing to compare the adjustment
  /// against.
  bool isWithinAllowedRange(
    TouristLocation current,
    double adjustedLat,
    double adjustedLon,
  ) {
    if (!current.isKnown) return true;
    return _distanceMetres(
          current.latitude,
          current.longitude,
          adjustedLat,
          adjustedLon,
        ) <=
        100;
  }

  /// Whether (lat, lon) is within Malaysia's (simplified) land boundary - a
  /// new landmark may only be submitted on Malaysian land (UC500, A9). Pure
  /// geometry, delegated to [LocationRules] - see its class doc for the
  /// boundary's accuracy caveat.
  bool isWithinMalaysia(double latitude, double longitude) =>
      LocationRules.isWithinMalaysia(latitude, longitude);

  /// Whether (lat, lon) is on Malaysian land (UC500, A9) - see
  /// [isWithinMalaysia] and [LocationRules.isOnLand].
  bool isOnLand(double latitude, double longitude) =>
      LocationRules.isOnLand(latitude, longitude);

  /// One food entry, resolved into the wire-shaped `LandmarkItem` this
  /// method's own submission expects. [entry.price] is always non-null by
  /// this point - `AddLandmarkViewModel` only calls [submitLandmark] once
  /// every food has passed its own completeness check.
  ///
  /// `imageUrl`/`imageId` come from [entry] - the ViewModel uploads each
  /// food's photo (via [uploadImage]) BEFORE calling [submitLandmark],
  /// so a food that has a photo persists with its `landmark_item.image_url`
  /// / `image_id` set; a food without one (e.g. name-typed, no photo)
  /// persists those as null.
  LandmarkItem _toLandmarkItem(
    FoodSubmission entry,
    String touristId, {
    int landmarkIdOverride = 0,
    int? localFoodIdOverride,
  }) {
    return LandmarkItem(
      id: 0,
      landmarkId:
          landmarkIdOverride, // 0 = assigned once the landmark is saved.
      touristId: touristId,
      // The curated catalogue row this dish resolves to - [localFoodIdOverride]
      // when the caller already knows it (the merge path resolves brand-new
      // foods' ids first, Option-C style), else `entry.food.id` when it is
      // already in `local_food` (id != 0), else 0 (a brand-new food gets its
      // id backfilled after the Option-C catalogue insert).
      localFoodId: localFoodIdOverride ?? entry.food.id,
      dish: entry.food.name,
      // LocalFood has no dedicated `variant` field (see FoodRecognitionLogic
      // - it is carried as a synonym instead).
      variant: entry.food.synonyms.isNotEmpty ? entry.food.synonyms.first : '',
      foodCategory: entry.food.category,
      description: entry.food.description,
      origin: entry.food.origin,
      culturalBackground: entry.food.culturalBackground,
      imageUrl: entry.imageUrl,
      imageId: entry.imageId,
      price: entry.price,
      priceMin: entry.priceMin,
      priceMax: entry.priceMax,
      seasonal: '', // TODO: no seasonal-tracking UI yet
      cookingStyle: entry.food.cookingStyle,
      mealType: entry.food.mealType,
      isFake: entry.isFake,
    );
  }

  /// Saves a new landmark (BF-24..28), OR merges the dishes into a place that
  /// already exists on the map (UC500 A13).
  ///
  /// MATCH RULE (A13): "the same place" = same name (trimmed, case-insensitive)
  /// AND within ~100m of the landmark's chosen location. Resolution order:
  ///   1. a catalogue RESTAURANT within ~100m  -> merge its `restaurant_item`
  ///      (no landmark row is written; the restaurant keeps its opening hours);
  ///   2. else an existing submitted LANDMARK within ~100m -> merge its
  ///      `landmark_item` (no new landmark row; the existing one keeps its
  ///      opening hours);
  ///   3. else a brand-new `submitted_landmark` is saved (always `available`,
  ///      `reported_count` 0).
  /// In EVERY outcome the place the tourist just re-confirmed is reactivated:
  /// the matched catalogue restaurant (1) and any same-name submitted
  /// landmark(s) within ~100m have their `report_count`/`reported_count`
  /// cleared and `status` set back to 'available' (A20) - including, in case
  /// (2), the very landmark being merged into.
  ///
  /// The dishes themselves are NOT attached here - genuinely-new foods get a
  /// `local_food` row (Option C) only after this returns, and the caller
  /// attaches them with the resolved ids (see
  /// [addFoodsToRestaurant]/[addFoodsToSubmittedLandmark]), so this method's
  /// result carries no added/existing dish lists yet.
  ///
  /// The landmark's own signboard/stall photo is carried on the submitted
  /// row too: [imageUrl]/[imageId] are its storage URL / object id and
  /// [imageCategory] is `'signboard'` or `'stall'` (see
  /// `AddLandmarkViewModel._capturedImageType`). The ViewModel uploads the
  /// photo (via [uploadImage]) before calling this - the same way it uploads
  /// each food's photo - so `submitted_landmark.image_url` / `image_id` /
  /// `image_category` are set, not null.
  Future<LandmarkSubmitResult> submitLandmark({
    required String restaurantName,
    required double? latitude,
    required double? longitude,
    required String category,
    required String touristId,
    String? imageUrl,
    String? imageId,
    String? imageCategory,
    required List<FoodSubmission> foods,
    required Map<Weekday, List<OpeningHour>> operatingHours,
  }) async {
    // 1) Same place as a catalogue restaurant (A13) -> merge into it.
    final Restaurant? existingRestaurant = await _findNearbyRestaurant(
      restaurantName,
      latitude,
      longitude,
    );
    if (existingRestaurant != null) {
      await _reactivateSamePlace(
        name: restaurantName,
        latitude: latitude,
        longitude: longitude,
        matchedRestaurant: existingRestaurant,
      );
      return LandmarkSubmitResult.mergedIntoRestaurant(
        restaurantId: existingRestaurant.id,
        targetName: existingRestaurant.name,
      );
    }

    // 2) Same place as an earlier submitted landmark -> merge into it too
    // (the user re-submitted in person; don't stack a second pin).
    final SubmittedLandmark? existingLandmark =
        await _findNearbySubmittedLandmark(restaurantName, latitude, longitude);
    if (existingLandmark != null) {
      await _reactivateSamePlace(
        name: restaurantName,
        latitude: latitude,
        longitude: longitude,
        matchedRestaurant: null,
      );
      return LandmarkSubmitResult.mergedIntoLandmark(
        landmarkId: existingLandmark.id,
        targetName: existingLandmark.name,
      );
    }

    // 3) Brand-new place - build the landmark + its items here, from the raw,
    // already-validated form data, and persist them following the real
    // Supabase tables (`submitted_landmark` + `landmark_item` +
    // `opening_hours`). The foods' taste tags were already normalised against
    // `food_preference` in the recognition flow (`FoodRecognitionLogic`) -
    // not repeated here.
    final SubmittedLandmark landmark = SubmittedLandmark(
      id: 0,
      name: restaurantName,
      latitude: latitude,
      longitude: longitude,
      category: category,
      reportedCount: 0,
      status: LandmarkStatus.available,
      imageUrl: imageUrl,
      imageId: imageId,
      imageCategory: imageCategory,
      items: <LandmarkItem>[
        for (final FoodSubmission entry in foods)
          _toLandmarkItem(entry, touristId),
      ],
      openingHours: operatingHours.values
          .expand((List<OpeningHour> rows) => rows)
          .toList(growable: false),
    );
    final int landmarkId = await repository.landmark.save(landmark);

    // The tourist standing here again confirms the place still exists - if an
    // OLDER submitted landmark of the same place is frozen/reported, clear it
    // (A20). The fresh row above is already available with reported_count 0.
    await _reactivateSamePlace(
      name: restaurantName,
      latitude: latitude,
      longitude: longitude,
      matchedRestaurant: null,
    );
    return LandmarkSubmitResult.created(landmarkId: landmarkId);
  }

  /// The catalogue restaurant that is the SAME place as the submission:
  /// name equals [name] AND within ~100m of ([latitude], [longitude]). Picks
  /// the nearest such restaurant; null when there is no location fix or no
  /// restaurant matches (a same-named restaurant in another town is NOT the
  /// same place - it must not swallow a submission).
  Future<Restaurant?> _findNearbyRestaurant(
    String name,
    double? latitude,
    double? longitude,
  ) async {
    if (latitude == null || longitude == null) return null;
    final List<Restaurant> candidates = await repository.restaurant
        .findByNameList(name);
    return nearestRestaurantWithinMetres(candidates, latitude, longitude);
  }

  /// The previously submitted landmark that is the SAME place as the
  /// submission (used when no catalogue restaurant is near): name equals
  /// [name] AND within ~100m of ([latitude], [longitude]); nearest wins.
  /// null when there is no location fix or no landmark matches.
  Future<SubmittedLandmark?> _findNearbySubmittedLandmark(
    String name,
    double? latitude,
    double? longitude,
  ) async {
    if (latitude == null || longitude == null) return null;
    final List<SubmittedLandmark> candidates = await repository.landmark
        .findByName(name);
    return nearestLandmarkWithinMetres(candidates, latitude, longitude);
  }

  /// Pure "nearest candidate within [maxMetres]" selector - unit-testable
  /// geometry shared by the merge flow (no repository/network needed).
  /// Candidates without coordinates are ignored. null when nothing is within
  /// range (a same-named place in another town must not be matched).
  @visibleForTesting
  static Restaurant? nearestRestaurantWithinMetres(
    List<Restaurant> candidates,
    double latitude,
    double longitude, {
    double maxMetres = 100,
  }) {
    Restaurant? nearest;
    double nearestDistance = double.infinity;
    for (final Restaurant candidate in candidates) {
      final double? lat = candidate.latitude;
      final double? lon = candidate.longitude;
      if (lat == null || lon == null) continue;
      final double distance = _distanceMetres(latitude, longitude, lat, lon);
      if (distance <= maxMetres && distance < nearestDistance) {
        nearestDistance = distance;
        nearest = candidate;
      }
    }
    return nearest;
  }

  /// Submitted-landmark twin of [nearestRestaurantWithinMetres].
  @visibleForTesting
  static SubmittedLandmark? nearestLandmarkWithinMetres(
    List<SubmittedLandmark> candidates,
    double latitude,
    double longitude, {
    double maxMetres = 100,
  }) {
    SubmittedLandmark? nearest;
    double nearestDistance = double.infinity;
    for (final SubmittedLandmark candidate in candidates) {
      final double? lat = candidate.latitude;
      final double? lon = candidate.longitude;
      if (lat == null || lon == null) continue;
      final double distance = _distanceMetres(latitude, longitude, lat, lon);
      if (distance <= maxMetres && distance < nearestDistance) {
        nearestDistance = distance;
        nearest = candidate;
      }
    }
    return nearest;
  }

  /// Reactivates a place the tourist just re-confirmed exists (A20), in BOTH
  /// submit outcomes (merge into an existing restaurant, and brand-new
  /// landmark):
  ///   * the matched catalogue [restaurant] (when given) has its
  ///     `report_count` / `status` cleared back to 'available';
  ///   * every previously submitted landmark with the same name within ~100m
  ///     of the submission also has `reported_count` / `status` cleared.
  /// Best-effort - a failed reactivation must never fail the submission.
  Future<void> _reactivateSamePlace({
    required String name,
    required double? latitude,
    required double? longitude,
    required Restaurant? matchedRestaurant,
  }) async {
    try {
      if (matchedRestaurant != null) {
        await repository.restaurant.resetRestaurantModeration(
          matchedRestaurant.id,
        );
      }
      if (latitude == null || longitude == null) return;
      final List<SubmittedLandmark> sameName = await repository.landmark
          .findByName(name);
      for (final SubmittedLandmark older in sameName) {
        final double? lat = older.latitude;
        final double? lon = older.longitude;
        if (lat == null || lon == null) continue;
        if (_distanceMetres(latitude, longitude, lat, lon) > 100) continue;
        await repository.landmark.clearReportsAndReactivate(older.id);
      }
    } catch (_) {
      // Ignored - the submission itself already succeeded.
    }
  }

  /// Attaches the submitted dishes to an existing catalogue restaurant as
  /// `restaurant_item` rows (the A13 restaurant merge, called after
  /// genuinely-new foods were registered to `local_food` so every item has a
  /// `local_food_id`). A dish that is already listed under the restaurant
  /// (same catalogue food or same name) is skipped (A13.1) and reported back
  /// in [FoodAttachResult.existing] so the UI can say "item exists".
  /// Best-effort per item - a failed link must not fail the merge; it is
  /// simply not reported as added.
  Future<FoodAttachResult> addFoodsToRestaurant(
    int restaurantId,
    List<FoodSubmission> foods,
    Map<String, int> newFoodIds,
  ) async {
    final List<String> added = <String>[];
    final List<String> existing = <String>[];
    final Set<String> existingNames = <String>{};
    final Set<int> existingFoodIds = <int>{};
    try {
      final List<RestaurantItem> existingItems = await repository.restaurant
          .getRestaurantItemsByRestaurantIds(<int>[restaurantId]);
      for (final RestaurantItem item in existingItems) {
        if (item.localFoodId > 0) existingFoodIds.add(item.localFoodId);
        existingNames.add(item.foodName.trim().toLowerCase());
      }
    } catch (_) {
      // Ignored - dedupe is best-effort; the insert below still runs.
    }

    for (final FoodSubmission entry in foods) {
      if (entry.isFake) continue;
      final String key = entry.food.name.trim().toLowerCase();
      final int localFoodId = newFoodIds[entry.food.name] ?? entry.food.id;
      if (localFoodId <= 0) continue; // Not in the catalogue - nothing to link.
      if ((localFoodId > 0 && existingFoodIds.contains(localFoodId)) ||
          existingNames.contains(key)) {
        if (!existing.contains(entry.food.name)) {
          existing.add(entry.food.name);
        }
        continue;
      }
      try {
        await repository.restaurant.addRestaurantItem(
          restaurantId: restaurantId,
          localFoodId: localFoodId,
          name: entry.food.name,
          foodImgUrl: entry.imageUrl,
          foodCategory: entry.food.category,
          price: entry.price,
        );
        added.add(entry.food.name);
        existingFoodIds.add(localFoodId);
        existingNames.add(key);
      } catch (_) {
        // Ignored - one bad item link must not abort the merge.
      }
    }
    return (added: added, existing: existing);
  }

  /// Attaches the submitted dishes to an EXISTING submitted landmark as
  /// `landmark_item` rows (the A13 landmark merge - used when the place is
  /// already a submitted landmark rather than a catalogue restaurant). Same
  /// dedupe/reporting as [addFoodsToRestaurant]; the landmark's own opening
  /// hours are untouched (A13.2).
  Future<FoodAttachResult> addFoodsToSubmittedLandmark({
    required int landmarkId,
    required String touristId,
    required List<FoodSubmission> foods,
    required Map<String, int> newFoodIds,
  }) async {
    final List<String> added = <String>[];
    final List<String> existing = <String>[];
    final Set<String> existingNames = <String>{};
    final Set<int> existingFoodIds = <int>{};
    try {
      final SubmittedLandmark? current = await repository.landmark
          .getSubmittedLandmarkById(landmarkId);
      if (current != null) {
        for (final LandmarkItem item in current.items) {
          if (item.localFoodId > 0) existingFoodIds.add(item.localFoodId);
          existingNames.add(item.dish.trim().toLowerCase());
        }
      }
    } catch (_) {
      // Ignored - dedupe is best-effort; the insert below still runs.
    }

    final List<LandmarkItem> toAdd = <LandmarkItem>[];
    for (final FoodSubmission entry in foods) {
      if (entry.isFake) continue;
      final String key = entry.food.name.trim().toLowerCase();
      final int localFoodId = newFoodIds[entry.food.name] ?? entry.food.id;
      if ((localFoodId > 0 && existingFoodIds.contains(localFoodId)) ||
          existingNames.contains(key)) {
        if (!existing.contains(entry.food.name)) {
          existing.add(entry.food.name);
        }
        continue;
      }
      toAdd.add(
        _toLandmarkItem(
          entry,
          touristId,
          landmarkIdOverride: landmarkId,
          localFoodIdOverride: localFoodId > 0 ? localFoodId : null,
        ),
      );
    }
    if (toAdd.isEmpty) return (added: added, existing: existing);
    await repository.landmark.addItems(landmarkId, toAdd);
    for (final LandmarkItem item in toAdd) {
      added.add(item.dish);
    }
    return (added: added, existing: existing);
  }

  /// Option C backfill: after genuinely-new foods are written to `local_food`,
  /// point the just-saved `landmark_item` rows at them (their `local_food_id`
  /// was 0 at insert time because the rows did not exist yet). Best-effort - a
  /// failed link must not fail the submission that already succeeded.
  Future<void> linkNewFoodsToLandmark(
    int landmarkId,
    Map<String, int> foodIds,
  ) async {
    for (final MapEntry<String, int> entry in foodIds.entries) {
      try {
        await repository.landmark.linkItemToFood(
          landmarkId,
          entry.key,
          entry.value,
        );
      } catch (_) {
        // Ignored - the landmark and its items are already saved.
      }
    }
  }

  /// Records a tourist's report against a submitted landmark (the shared
  /// `report` table) and applies the moderation rule: `reported_count` is
  /// incremented, and once it reaches [_reportFreezeAtReports] the landmark
  /// is frozen (`status` 'frozen') so the map/list filters stop showing it.
  /// `frozePlace: true` tells the caller that THIS report was the one that
  /// froze it - the UI leaves the page and refreshes the map, dropping the
  /// now-hidden pin.
  ///
  /// Reporting is a signed-in feature: when no tourist is resolved (no auth
  /// session) nothing is written and `requiresSignIn: true` is returned so
  /// the UI can ask the user to sign in. When signed in, one tourist may
  /// report a place only once - a duplicate is detected first and
  /// `alreadyReported: true` is returned without touching the count.
  Future<({bool requiresSignIn, bool alreadyReported, bool frozePlace})>
  submitLandmarkReport({
    required int landmarkId,
    required LandmarkReportReason reason,
    String? touristId,
  }) async {
    final String? resolvedTouristId =
        touristId ?? await repository.auth.currentTouristId();
    if (resolvedTouristId == null || resolvedTouristId.isEmpty) {
      return (requiresSignIn: true, alreadyReported: false, frozePlace: false);
    }
    final bool duplicate = await repository.report.alreadyReported(
      kind: 'landmark',
      placeId: landmarkId,
      touristId: resolvedTouristId,
    );
    if (duplicate) {
      return (requiresSignIn: false, alreadyReported: true, frozePlace: false);
    }
    await repository.report.insertReport(
      kind: 'landmark',
      placeId: landmarkId,
      reason: reason.name,
      touristId: resolvedTouristId,
    );
    final int count = await repository.landmark.incrementReportCount(
      landmarkId,
    );
    final bool frozePlace = shouldFreezeAfterReport(count);
    if (frozePlace) {
      await repository.landmark.freeze(landmarkId);
      // Frozen places are no longer 'available', so cached map pins must go:
      // the next read (right after the UI leaves the page) has no pin for it.
      repository.map.clearCache();
    }
    return (
      requiresSignIn: false,
      alreadyReported: false,
      frozePlace: frozePlace,
    );
  }

  /// Freeze once the reported count REACHES [_reportFreezeAtReports] (so the
  /// 5th report freezes). Pure so the boundary is unit-testable without a
  /// repository seam.
  @visibleForTesting
  static bool shouldFreezeAfterReport(int reportedCount) =>
      reportedCount >= _reportFreezeAtReports;

  /// A landmark is frozen once its report count reaches this many reports.
  static const int _reportFreezeAtReports = 5;
}

/// Result of attaching a set of submitted dishes to an existing place -
/// which dishes were added and which already existed (A13.1) - so the UI can
/// say "item exists" after a merge.
typedef FoodAttachResult = ({List<String> added, List<String> existing});

/// Which of the three submit outcomes happened - see
/// [LandmarkSubmissionLogic.submitLandmark].
enum LandmarkSubmitOutcome { created, mergedIntoRestaurant, mergedIntoLandmark }

/// Outcome of [LandmarkSubmissionLogic.submitLandmark] - a brand-new
/// `submitted_landmark` was created, or the dishes were MERGED into an
/// existing catalogue restaurant / submitted landmark (same name within
/// ~100m) and no new landmark row was written.
class LandmarkSubmitResult {
  const LandmarkSubmitResult.created({required this.landmarkId})
    : outcome = LandmarkSubmitOutcome.created,
      restaurantId = null,
      targetName = null,
      addedDishNames = const <String>[],
      existingDishNames = const <String>[];

  const LandmarkSubmitResult.mergedIntoRestaurant({
    required this.restaurantId,
    required this.targetName,
  }) : outcome = LandmarkSubmitOutcome.mergedIntoRestaurant,
       landmarkId = null,
       addedDishNames = const <String>[],
       existingDishNames = const <String>[];

  const LandmarkSubmitResult.mergedIntoLandmark({
    required this.landmarkId,
    required this.targetName,
  }) : outcome = LandmarkSubmitOutcome.mergedIntoLandmark,
       restaurantId = null,
       addedDishNames = const <String>[],
       existingDishNames = const <String>[];

  const LandmarkSubmitResult._({
    required this.outcome,
    this.landmarkId,
    this.restaurantId,
    this.targetName,
    required this.addedDishNames,
    required this.existingDishNames,
  });

  final LandmarkSubmitOutcome outcome;

  /// The NEW landmark's id when [outcome] is [created]; the EXISTING
  /// landmark's id when [mergedIntoLandmark]; null when merged into a
  /// catalogue restaurant.
  final int? landmarkId;

  /// The catalogue restaurant's id when [outcome] is [mergedIntoRestaurant].
  final int? restaurantId;

  /// Display name of the place merged into (restaurant or landmark), for the
  /// confirmation message; null when a new landmark was created.
  final String? targetName;

  /// Dishes actually attached - filled in by the caller once genuinely-new
  /// foods were registered, via [copyWith].
  final List<String> addedDishNames;

  /// Dishes NOT attached because they already exist on the target (A13.1).
  final List<String> existingDishNames;

  /// Whether the dishes went onto an existing place instead of a new landmark.
  bool get merged =>
      outcome == LandmarkSubmitOutcome.mergedIntoRestaurant ||
      outcome == LandmarkSubmitOutcome.mergedIntoLandmark;

  LandmarkSubmitResult copyWith({
    List<String>? addedDishNames,
    List<String>? existingDishNames,
  }) => LandmarkSubmitResult._(
    outcome: outcome,
    landmarkId: landmarkId,
    restaurantId: restaurantId,
    targetName: targetName,
    addedDishNames: addedDishNames ?? this.addedDishNames,
    existingDishNames: existingDishNames ?? this.existingDishNames,
  );
}
