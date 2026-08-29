import 'dart:math' as math;

import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
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
    return response.textDetected!;
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
  double _distanceMetres(double lat1, double lon1, double lat2, double lon2) {
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

  double _degToRad(double deg) => deg * (math.pi / 180);

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
  LandmarkItem _toLandmarkItem(FoodSubmission entry, String touristId) {
    return LandmarkItem(
      id: 0,
      landmarkId: 0, // Assigned once the landmark itself is saved.
      touristId: touristId,
      // The curated catalogue row this dish resolves to - `entry.food.id`
      // when it is already in `local_food` (id != 0), else 0 (a brand-new
      // food gets its id backfilled after the Option-C catalogue insert).
      localFoodId: entry.food.id,
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

  /// Saves a new landmark (BF-24..28) - builds the `SubmittedLandmark` and
  /// `LandmarkItem` domain objects here, from the raw, already-validated
  /// form data `AddLandmarkViewModel` passes in. This construction (and its
  /// business defaults - `reportedCount: 0`, `status: available`) used to
  /// happen in the ViewModel itself; moved here since deciding a landmark's
  /// initial moderation state is a domain concern, not a form concern.
  ///
  /// A new landmark is ALWAYS submitted as [LandmarkStatus.available] with
  /// `reported_count` 0 - i.e. even if a previous frozen landmark of the
  /// same name exists, the fresh submission starts available and clean (the
  /// repository forces these two values on insert too, so the guarantee
  /// holds regardless of what is passed in).
  ///
  /// The landmark's own signboard/stall photo is carried on the submitted
  /// row too: [imageUrl]/[imageId] are its storage URL / object id and
  /// [imageCategory] is `'signboard'` or `'stall'` (see
  /// `AddLandmarkViewModel._capturedImageType`). The ViewModel uploads the
  /// photo (via [uploadImage]) before calling this - the same way it uploads
  /// each food's photo - so `submitted_landmark.image_url` / `image_id` /
  /// `image_category` are set, not null.
  ///
  /// TODO once `SubmittedLandmarkRepository` has real methods:
  ///  - if [checkRestaurantExists] found a match: A13 - check whether it is
  ///    frozen and reactivate it (A20), check the food isn't already listed
  ///    under it (A13.1), then add just the new item(s) and keep its
  ///    existing opening hours (A13.2) rather than overwriting them;
  ///  - otherwise: save the new landmark as a brand new submission.
  ///
  /// @return the assigned `landmark_id`, or `0` when no new landmark was
  ///         created (a matching restaurant already exists). The submit flow
  ///         uses it to backfill brand-new foods' ids onto the items (Option C).
  Future<int> submitLandmark({
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
    final Restaurant? existing = await checkRestaurantExists(restaurantName);
    if (existing != null) {
      // TODO: A13/A13.1/A13.2/A20 handling once SubmittedLandmarkRepository
      // exposes "add item to existing landmark" and "reactivate" methods.
      return 0;
    }

    // Build the landmark + its items here, from the raw, already-validated
    // form data, and persist them following the real Supabase tables
    // (`submitted_landmark` + `landmark_item` + `opening_hours`). The foods'
    // taste tags were already normalised against `food_preference` in the
    // recognition flow (`FoodRecognitionLogic`) - not repeated here.
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
    return landmarkId;
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
}
