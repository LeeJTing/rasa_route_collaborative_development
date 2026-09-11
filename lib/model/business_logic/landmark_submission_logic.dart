import 'dart:math' as math;

import 'package:meta/meta.dart' show visibleForTesting;

import '../../core/name_normalization.dart';
import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/landmark_repository_facade.dart';
import 'food_name_matcher.dart';
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
  /// EXACT signboard text, e.g. "海天楼" - the romanised translation is not
  /// appended, and a transcription Gemini "turned" into the other Chinese
  /// style is restyled to the style it reported for the sign (see
  /// [displaySignboardName]). The tourist can edit the field afterwards.
  /// Errors: A2 (timeout), A7 (no text), A19 (incomplete frame)
  Future<String> analyzeSignboard(List<int> imageBytes) async {
    final response = await repository.recognition.analyzeSignboard(imageBytes);
    if (response.signboardImageStatus != 'complete') {
      throw Exception(
        'Signboard not fully in frame. Please ensure the entire signboard is visible.',
      );
    }
    // Either form can name the field: a Latin signboard supplies only
    // `textDetected`, a non-Latin one supplies the original script as well
    // (and THAT is what gets shown - see [displaySignboardName]).
    final String name = displaySignboardName(
      romanised: sanitiseSignboardName(response.textDetected ?? ''),
      originalScript: response.nameOriginalScript,
      languageScript: response.languageScript,
      scriptVariant: response.scriptVariant,
    );
    if (name.trim().isEmpty) {
      // No text at all, or only noise (e.g. a lone phone number) - nothing to
      // auto-fill, the same A7 outcome either way.
      throw Exception('Unable to extract restaurant name from signboard.');
    }
    return name;
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
  /// - non-Latin signs (Chinese/Tamil/Jawi) return the EXACT signboard text,
  ///   e.g. "海天楼" - the romanised translation is deliberately NOT appended
  ///   in parentheses;
  /// - everything else returns the romanised name (the sign's own text when
  ///   it is Latin, or the only form Gemini supplied).
  ///
  /// [scriptVariant] is the Chinese style Gemini says is PAINTED on the
  /// sign. When the transcription contradicts it - the model "turned" the
  /// words into the other style instead of copying them (see
  /// [isScriptVariantContradiction]) - the DETECTED style wins: the
  /// transcription is converted BACK to it wherever the app can prove the
  /// intended glyph ([correctChineseScriptStyle]), so a Traditional sign
  /// reported as Traditional can never surface as Simplified ("天义" is
  /// returned as "天義"). Only a contradiction that cannot be fully
  /// corrected falls back to the romanised name; the original is kept only
  /// when there is nothing else to show.
  static String displaySignboardName({
    required String romanised,
    String? originalScript,
    String languageScript = 'latin',
    String scriptVariant = 'n/a',
  }) {
    final String? original = originalScript == null
        ? null
        : sanitiseSignboardName(originalScript);
    final bool useOriginal =
        original != null &&
        original.isNotEmpty &&
        original != romanised &&
        languageScript != 'latin';
    if (!useOriginal) return romanised;
    if (!isScriptVariantContradiction(
      text: original,
      scriptVariant: scriptVariant,
    )) {
      return original;
    }
    // The model contradicted its OWN style report: the sign is said to be
    // painted in one style, yet the transcription carries the other one.
    // The detected style wins - restore the transcription to it where the
    // conversion is provable ("义" can only have been painted as "義"),
    // never the model's habit over the sign. Only a contradiction the app
    // cannot fully correct loses to the romanised name.
    final String corrected = correctChineseScriptStyle(original, scriptVariant);
    if (corrected != original &&
        !isScriptVariantContradiction(
          text: corrected,
          scriptVariant: scriptVariant,
        )) {
      return corrected;
    }
    return romanised.isNotEmpty ? romanised : original;
  }

  /// The script-variant CHECK for a signboard transcription: Gemini copies
  /// the characters off the sign, but it sometimes "turns" Chinese names
  /// into the other style (Traditional for a Simplified sign or vice versa).
  /// The response says which style is painted on the sign ([scriptVariant],
  /// read from the image); a transcription carrying the opposite style's
  /// glyphs - or mixing the two on a one-style sign - contradicts it, so it
  /// cannot be an exact copy of the signboard.
  ///
  /// Only a definite clash counts: a "mixed"/"n/a" claim, or a name made
  /// entirely of glyphs shared by both styles ("海天"), never conflicts.
  static bool isScriptVariantContradiction({
    required String text,
    required String scriptVariant,
  }) {
    final String style = chineseScriptStyleOf(text);
    switch (scriptVariant) {
      case 'simplified':
        return style == 'traditional' || style == 'mixed';
      case 'traditional':
        return style == 'simplified' || style == 'mixed';
      default:
        return false;
    }
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

  /// Shortest allowed single operating-hours row, in minutes. A row is one
  /// continuous open period, so a "09:00-09:30" row is not a meaningful
  /// answer for a restaurant - the tourist should either give the real
  /// period or mark the day differently. See [validateOperatingHours].
  static const int minimumOperatingRowMinutes = 60;

  /// Validates the operating-hours rules that are domain invariants - true
  /// of an `OpeningHour` no matter where the data came from, unlike a
  /// completeness check ("did the tourist fill in both times"), which stays
  /// in `AddLandmarkViewModel` since it's only meaningful because a human is
  /// mid-way through filling in a form (BF-19..23):
  ///  - closing time must be strictly after opening time - no overnight
  ///    wrap-around, since "24:00" already exists to express "open until
  ///    midnight" without needing to cross into the next day;
  ///  - a single row must be at least [minimumOperatingRowMinutes] long
  ///    (e.g. "09:00-09:30" on one row is rejected);
  ///  - multiple rows for the same day must not overlap (e.g.
  ///    "12:00-15:00" and "14:00-18:00" on the same day is invalid);
  ///  - multiple rows for the same day must not be CONTIGUOUS - one ending
  ///    exactly when the next begins ("09:00-12:00" + "12:00-14:00") is one
  ///    continuous period written as two rows and must be combined into a
  ///    single row ("09:00-14:00").
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
        if (row.closesAt! - row.opensAt! < minimumOperatingRowMinutes) {
          return '$dayName has a row shorter than 1 hour '
              '(${_timeLabel(row.opensAt!)}-${_timeLabel(row.closesAt!)}) - '
              'each opening-hours row must be at least 1 hour.';
        }
        ranges.add((row.opensAt!, row.closesAt!));
      }

      ranges.sort((a, b) => a.$1.compareTo(b.$1));
      for (int i = 1; i < ranges.length; i++) {
        if (ranges[i].$1 < ranges[i - 1].$2) {
          return "$dayName's operating hours overlap - please adjust the times.";
        }
        if (ranges[i].$1 == ranges[i - 1].$2) {
          return "$dayName's rows ${_timeLabel(ranges[i - 1].$1)}-"
              '${_timeLabel(ranges[i - 1].$2)} and '
              '${_timeLabel(ranges[i].$1)}-${_timeLabel(ranges[i].$2)} are '
              'continuous - combine them into one row '
              '${_timeLabel(ranges[i - 1].$1)}-${_timeLabel(ranges[i].$2)}.';
        }
      }
    }
    return null;
  }

  /// "HH:MM" for a minutes-since-midnight value (1440 renders as "24:00"),
  /// used in the operating-hours validation messages.
  static String _timeLabel(int minutes) {
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${mins.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------------------------
  // Same-restaurant capture range (A9-2): every photo that belongs to ONE
  // landmark must be captured within [sameRestaurantCaptureRangeMetres] of
  // where the first food was captured - the first capture's fix is the
  // restaurant's location for the whole form. Two photos further apart than
  // that are almost certainly two different restaurants, so the second one
  // is not allowed to join the submission.
  // ---------------------------------------------------------------------------

  /// Maximum distance between the first captured food's location and any
  /// later capture (additional food, signboard or stall) for it to count as
  /// the same restaurant.
  static const double sameRestaurantCaptureRangeMetres = 50;

  /// How far apart two forms' first-food spots may be and still describe the
  /// SAME restaurant when they also carry the same restaurant name - the
  /// range behind [matchingDraftForRestaurant] (the Add-Landmark form's
  /// Confirm action combines the two instead of keeping two unfinished
  /// submissions for one restaurant).
  static const double restaurantFormMergeRangeMetres = 100;

  /// Haversine distance between two fixes, in metres - the public form of
  /// the pure calculation used by [isWithinAllowedRange] and the
  /// same-restaurant check.
  double distanceMetres(TouristLocation a, TouristLocation b) =>
      _distanceMetres(a.latitude, a.longitude, b.latitude, b.longitude);

  /// Whether [captured] is close enough to [firstFoodLocation] to belong to
  /// the same restaurant. Always allowed (true) when either fix is unknown -
  /// with no GPS there is nothing to compare, and the tourist is never
  /// blocked by a missing fix.
  bool isSameRestaurantCaptureRange(
    TouristLocation firstFoodLocation,
    TouristLocation captured,
  ) {
    if (!firstFoodLocation.isKnown || !captured.isKnown) return true;
    return distanceMetres(firstFoodLocation, captured) <=
        sameRestaurantCaptureRangeMetres;
  }

  /// User-facing message when a capture fails the same-restaurant check.
  /// [capturedWhat] names the rejected capture, e.g. "This food" or
  /// "This signboard photo".
  ///
  /// Deliberately SHORT and consistent with the other capture messages
  /// ("No food detected in image. Please try again."): state the problem,
  /// then the action. The recognition card and the capture popup already
  /// carry their own "capture again" action lines, so this must not repeat
  /// the whole rule (the old wording did, and read like a paragraph).
  String captureTooFarMessage(String capturedWhat) =>
      '$capturedWhat was captured more than '
      '${sameRestaurantCaptureRangeMetres.round()} m from the first food. '
      'Move closer to the restaurant and capture again.';

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

  /// The recognised dish's Gemini-suggested price range as a plain display
  /// line - "Suggested price: RM 4.50 - RM 8.50", or a single value when the
  /// two bounds coincide. Null when no range is known (either bound <= 0, or
  /// max < min).
  ///
  /// Deliberately separate from [suggestedPriceWarning]: the range line is
  /// INFORMATIONAL and is shown whenever it is known - including while the
  /// typed value is still invalid - so the tourist can see the expected
  /// range while fixing the number. The warning is the stronger out-of-range
  /// nudge, shown only for an otherwise-valid price.
  String? suggestedPriceRangeText(double priceMin, double priceMax) {
    if (priceMin <= 0 || priceMax < priceMin) return null;
    final String min = priceMin.toStringAsFixed(2);
    if (priceMax == priceMin) return 'Suggested price: RM $min';
    return 'Suggested price: RM $min - RM ${priceMax.toStringAsFixed(2)}';
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
      // The name the tourist actually saw / typed, when it EXTENDS the
      // dictionary dish into an unlisted variant (`Cendol Jagung` ->
      // `Cendol`) - carried explicitly from recognition (see
      // `FoodSubmission.variant`).
      variant: entry.variant,
      foodCategory: entry.food.category,
      description: entry.food.description,
      origin: entry.food.origin,
      culturalBackground: entry.food.culturalBackground,
      // The VARIANT's own facts: ingredients observed on the photo (falling
      // back to the dictionary row's text) and the restrictions that apply
      // (observed tags when an analysis ran, else the dictionary links).
      ingredients: entry.food.ingredients,
      dietaryRestrictions: entry.dietaryRestrictions,
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
  ///      `landmark_item` (no new landmark row). The existing row KEEPS its
  ///      opening hours except for days the re-submission actually asserted
  ///      and changed (see [updateOpeningHoursOnMerge]) - a day left Unknown
  ///      keeps its stored hours;
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
    String? phone,
    String? website,
    String? address,
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
      // The merge only attaches dishes - but if the tourist supplied contact/
      // address details this time, persist them onto the existing row too
      // (they would otherwise be silently dropped). Best-effort: a contact
      // save failure must not fail the already-succeeded merge.
      try {
        await repository.landmark.updateContactFields(
          existingLandmark.id,
          phone: phone,
          website: website == null ? null : sanitiseWebsiteForSave(website),
          address: address,
        );
      } catch (_) {
        // Ignored - the merge itself succeeded.
      }
      // Opening hours follow the SAME per-field merge rule as contact data:
      // only days the re-submission actually asserted (Open/Closed) and that
      // changed are written onto the existing landmark - days left Unknown
      // keep their stored hours. Best-effort like the contact write.
      try {
        await repository.landmark.updateOpeningHoursOnMerge(
          existingLandmark.id,
          operatingHours,
        );
      } catch (_) {
        // Ignored - the merge itself succeeded.
      }
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
      phone: phone ?? '',
      website: sanitiseWebsiteForSave(website ?? ''),
      address: address ?? '',
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
  /// dedupe/reporting as [addFoodsToRestaurant], except that the identity is
  /// dish + VARIANT ([sameDishAndVariantIdentity]): the landmark already
  /// "has" a dish only when it holds the very same variant, so "Cendol
  /// Jagung" still joins a landmark that lists plain "Cendol" (and the
  /// confirmation names the variant, not the dictionary dish). The
  /// landmark's own opening hours are NOT touched here (A13.2) - the hours
  /// merge happens once, in [submitLandmark]'s merge branch, via
  /// [updateOpeningHoursOnMerge], so this dish-attach step stays
  /// single-purpose.
  Future<FoodAttachResult> addFoodsToSubmittedLandmark({
    required int landmarkId,
    required String touristId,
    required List<FoodSubmission> foods,
    required Map<String, int> newFoodIds,
  }) async {
    final List<String> added = <String>[];
    final List<String> existing = <String>[];
    final List<({String dish, int localFoodId, String variant})> listed =
        <({String dish, int localFoodId, String variant})>[];
    try {
      final SubmittedLandmark? current = await repository.landmark
          .getSubmittedLandmarkById(landmarkId);
      if (current != null) {
        for (final LandmarkItem item in current.items) {
          listed.add((
            dish: item.dish,
            localFoodId: item.localFoodId,
            variant: item.variant,
          ));
        }
      }
    } catch (_) {
      // Ignored - dedupe is best-effort; the insert below still runs.
    }

    final List<LandmarkItem> toAdd = <LandmarkItem>[];
    for (final FoodSubmission entry in foods) {
      if (entry.isFake) continue;
      final int localFoodId = newFoodIds[entry.food.name] ?? entry.food.id;
      final String label = dishLabel(entry.food.name, entry.variant);
      // "Already there" means the SAME dish AND the same variant - a
      // different variant is a different dish to list.
      final bool alreadyListed = listed.any(
        (row) => sameDishAndVariantIdentity(
          dish: row.dish,
          localFoodId: row.localFoodId,
          variant: row.variant,
          otherDish: entry.food.name,
          otherLocalFoodId: localFoodId,
          otherVariant: entry.variant,
        ),
      );
      if (alreadyListed) {
        if (!existing.contains(label)) existing.add(label);
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
      // A second copy inside the SAME submission is a duplicate too.
      listed.add((
        dish: entry.food.name,
        localFoodId: localFoodId,
        variant: entry.variant,
      ));
    }
    if (toAdd.isEmpty) return (added: added, existing: existing);
    await repository.landmark.addItems(landmarkId, toAdd);
    for (final LandmarkItem item in toAdd) {
      added.add(dishLabel(item.dish, item.variant));
    }
    return (added: added, existing: existing);
  }

  /// The name to REPORT for a submitted dish (the A13 confirmation, the
  /// report picker, the landmark pages) - its VARIANT when it has one (that
  /// is what the tourist captured: "Cendol Jagung"), else the dictionary
  /// dish name. One rule, so every list names a dish the same way.
  static String dishLabel(String dish, String variant) =>
      variant.trim().isEmpty ? dish : variant.trim();

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

  // =========================================================================
  // Add-Landmark contact / address rules (pure, unit-testable)
  // =========================================================================

  /// Field caps / thresholds for the Add New Landmark form.
  ///
  /// Restaurant name: typing STOPS at [maxRestaurantNameLength] (40, input is
  /// cut off no matter what is pasted), a WARNING shows from
  /// [restaurantNameWarnFromLength] (31), and submit is only allowed up to
  /// [restaurantNameSubmitMaxLength] (30).
  ///
  /// Website: typing STOPS at [maxWebsiteLength] (2048 - the practical URL
  /// ceiling), and an amber WARNING shows from [websiteWarnFromLength]
  /// (2043) as the tourist approaches it. There is no separate submit
  /// limit: any link that fits the cap and passes [isValidWebsiteFormat]
  /// may be submitted.
  ///
  /// Phone counts FORMATTED text (e.g. "+60 12-345 6789" = 16 chars; the
  /// digits themselves are at most ~12). Address is capped at 150.
  static const int maxRestaurantNameLength = 40;
  static const int restaurantNameSubmitMaxLength = 30;
  static const int restaurantNameWarnFromLength = 31;

  static const int maxPhoneLength = 18;

  static const int maxWebsiteLength = 2048;

  /// The website's amber "stay under" warning starts here - 5 characters
  /// before the [maxWebsiteLength] hard stop.
  static const int websiteWarnFromLength = 2043;

  static const int maxAddressLength = 150;

  /// Manual food-name entry (the recognition screen's "Wrong dish? Type the
  /// name" / "Show this food" fields).
  ///
  /// Typing STOPS at [maxFoodNameLength] (50) - enforced by the TextField -
  /// and from [foodNameWarnFromLength] (45) an amber warning asks the
  /// tourist to keep the dish name short: a dish name is a LABEL, not a
  /// description, and an over-long one would be written into the landmark
  /// item, the catalogue row and the database column behind them.
  static const int maxFoodNameLength = 50;
  static const int foodNameWarnFromLength = 45;

  /// Amber "getting long" warning for the manual food-name entry - null
  /// while the name is a normal length. Counts the TRIMMED value (exactly
  /// what `FoodRecognitionViewModel.enterFoodName` would submit), so stray
  /// leading/trailing spaces do not trip it early.
  String? foodNameLengthWarning(String foodName) {
    final String value = foodName.trim();
    if (value.length < foodNameWarnFromLength) return null;
    return 'Food name should stay under $maxFoodNameLength characters '
        '(currently ${value.length}).';
  }

  static String _phoneDigits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');

  /// Whether [value] is a plausible MALAYSIAN phone number - format-level
  /// only (the app cannot verify the number is real/active without an SMS
  /// OTP, which needs a backend provider). Accepts +60 / 0060 / 0 national
  /// prefixes with spaces, hyphens, parens and dots anywhere in between.
  /// STRICT: mobile must be 01x-xxxxxxx/01xx-xxxxxx (national length 9-10);
  /// landline must be a real MY area code (0[3-9]..., so "02" Jakarta-style
  /// prefixes are rejected) with national length 8-10.
  bool isValidMalaysianPhone(String value) {
    String national = _phoneDigits(value);
    if (national.isEmpty) return false;
    if (national.startsWith('0060')) {
      national = national.substring(4);
    } else if (national.startsWith('60')) {
      national = national.substring(2);
    } else if (national.startsWith('0')) {
      national = national.substring(1);
    } else {
      return false;
    }
    if (national.length < 8 || national.length > 10) return false;
    if (national.startsWith('1')) {
      // Mobile: 01x / 011x - national 9-10 digits.
      return RegExp(r'^1[0-9]\d{7,8}$').hasMatch(national);
    }
    // Landline: area code starts 3-9 (03,04,...,09 or 08x) - never '2'.
    return RegExp(r'^[3-9]\d{7,8}$').hasMatch(national);
  }

  /// The characters a URL may contain, per RFC 3986: unreserved
  /// (`A-Z a-z 0-9 - . _ ~`), gen-delims (`: / ? # [ ] @`) and sub-delims
  /// (`! $ & ' ( ) * + , ; =`), plus `%XX` percent-encoded triplets.
  /// Anything else - spaces, tabs, non-ASCII text, quotes, backslashes,
  /// angle brackets - makes the value NOT a URL.
  static final RegExp _urlCharacters = RegExp(
    r"^(?:[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=]|%[0-9A-Fa-f]{2})+$",
  );

  /// True when [value] contains more than one URL scheme marker (`://`) -
  /// a pasted "https://a.comhttps://b.com" (no space between the links, so
  /// the whitespace rule never fires) or a second scheme embedded later in
  /// the path/query is a LIST of links, or one link smuggling another,
  /// never a single website. The check deliberately runs on the raw text:
  /// parsing would happily accept "a.comhttps" as one valid host label.
  bool websiteContainsMultipleUrls(String value) =>
      '://'.allMatches(value).length > 1;

  /// Whether [value] is a syntactically valid PUBLIC http(s) website URL.
  /// STRICT, per RFC 3986 and the XSS rules for stored links:
  ///  * the scheme is MANDATORY and must be `http://` or `https://` - so
  ///    `example.com`, `ftp://...` and script schemes such as `javascript:`
  ///    or `data:` can never pass;
  ///  * exactly ONE link - a second `://` anywhere (a glued paste like
  ///    `https://a.comhttps://b.com`, or another scheme embedded in the
  ///    path/query) is rejected: the value is one website, never a list;
  ///  * every character must be from the RFC 3986 set, with `%XX` for
  ///    anything encoded - links may NOT contain spaces (a space is
  ///    rejected, not silently turned into `%20`);
  ///  * no embedded credentials (`user:pass@`), the host must be a proper
  ///    dotted domain - each label alphanumeric/hyphen, a TLD of >=2 letters
  ///    (or a punycode `xn--` TLD) - and localhost / IP-literal hosts are
  ///    rejected (they are not public restaurant websites);
  ///  * the value is capped at [maxWebsiteLength] (2048) characters.
  /// Storage additionally strips any HTML tags ([sanitiseWebsiteForSave]).
  /// Reachability is a separate, network-backed check
  /// ([isWebsiteReachable]) - a valid format does not mean the site exists.
  bool isValidWebsiteFormat(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxWebsiteLength) return false;
    // Mandatory web scheme - also the XSS guard: `javascript:`, `data:`,
    // `vbscript:` can never satisfy it (RFC 3986 schemes are
    // case-insensitive, so the check is too).
    final String lower = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return false;
    }
    // ONE link only - a second scheme marker makes this a list of links
    // (see [websiteContainsMultipleUrls]); the character and host checks
    // below cannot see it, because a glued host like "a.comhttps" parses
    // as a perfectly valid domain label.
    if (websiteContainsMultipleUrls(trimmed)) return false;
    // RFC 3986 characters only - this rejects spaces, tabs, non-ASCII text
    // and any "<...>" markup a paste might carry.
    if (!_urlCharacters.hasMatch(trimmed)) return false;
    // Reject any embedded credentials - '@' in the authority portion. (Dart's
    // Uri does not reliably surface `user:pass@` as `userInfo`, so check the
    // raw authority text instead of relying on that property.)
    final int afterScheme = trimmed.indexOf('://') + 3;
    if (afterScheme >= trimmed.length ||
        trimmed.substring(afterScheme).contains('@')) {
      return false;
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return false;
    final String host = uri.host.toLowerCase();
    if (host == 'localhost') return false;
    // Reject IPv4 literals (e.g. http://192.168.1.1).
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return false;
    final List<String> labels = host.split('.');
    if (labels.length < 2 || labels.any((String label) => label.isEmpty)) {
      return false;
    }
    // Each label must be alphanumeric/hyphen (no leading/trailing hyphen).
    final bool validLabels = labels.every(
      (String label) =>
          RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(label),
    );
    if (!validLabels) return false;
    final String tld = labels.last;
    final bool validTld =
        tld.length >= 2 &&
        (RegExp(r'^[a-z]{2,}$').hasMatch(tld) || tld.startsWith('xn--'));
    return validTld;
  }

  /// True when [value] contains whitespace - a link may never contain a
  /// space (RFC 3986); pasted "https://my site.com" gets its own message
  /// instead of being silently percent-encoded into a different URL.
  bool websiteContainsWhitespace(String value) => RegExp(r'\s').hasMatch(value);

  /// The website value actually SAVED to the database: HTML tags stripped,
  /// control characters removed, trimmed. The field validator already
  /// rejects such input ([isValidWebsiteFormat]); this is the belt-and-
  /// braces rule that guarantees a stored "link" is plain text - never
  /// `<script>`/`<a>` markup - on every save path (form, draft, merge).
  ///
  /// Whole `script`/`style` ELEMENTS are removed first (tags AND their
  /// contents, so "…com<script>alert(1)</script>" cannot keep "alert(1)");
  /// for every other tag only the markup is stripped, leaving the text
  /// inside as plain text.
  static String sanitiseWebsiteForSave(String value) => value
      .replaceAll(
        RegExp(
          r'<(script|style)\b[^>]*>.*?</\1\s*>',
          caseSensitive: false,
          dotAll: true,
        ),
        '',
      )
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .trim();

  /// Whether [value] is acceptable free text for the optional restaurant
  /// address. STRICT: letters/digits (any script, so Chinese addresses
  /// work), spaces and common address punctuation ONLY - no control
  /// characters/newlines - and at least one LETTER is required (a string of
  /// nothing but digits/punctuation is not an address).
  bool isValidAddressText(String value) {
    if (containsControlCharacters(value)) return false;
    final bool safeChars = RegExp(
      r"^[\p{L}\p{N}\s.,#\-/()'&+]+$",
      unicode: true,
    ).hasMatch(value);
    if (!safeChars) return false;
    return RegExp(r'\p{L}', unicode: true).hasMatch(value);
  }

  /// Whether [value] is acceptable for the restaurant name. STRICT: letters
  /// or digits of any script, spaces and common name punctuation only; no
  /// control characters; and at least one letter/digit is required (a name
  /// made solely of symbols/punctuation is not a name).
  bool isValidRestaurantNameText(String value) {
    if (containsControlCharacters(value)) return false;
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(value)) {
      return false;
    }
    return RegExp(
      r"^[\p{L}\p{N}\s&.'#,\-():/]+$",
      unicode: true,
    ).hasMatch(value);
  }

  /// True when [value] contains control characters (0x00-0x1F, 0x7F) - a
  /// blanket guard applied to every free-text form field so pasted content
  /// can never smuggle in newlines/control bytes.
  bool containsControlCharacters(String value) =>
      value.contains(RegExp(r'[\x00-\x1F\x7F]'));

  /// Whether [url] answers a GET within 5s with HTTP 200-399 - the website
  /// field's reachability check (see `LinkCheckRepository`). Best-effort
  /// from the client for form validation; a production deployment should
  /// run the equivalent check server-side (SSRF).
  Future<bool> isWebsiteReachable(String url) =>
      repository.links.isWebsiteReachable(url);

  // ===========================================================================
  // Dev GPS mock (Android-only presenter tool)
  // ===========================================================================
  //
  // The capture screen drives the SAME mock singleton the dashboard drives
  // (`MockLocationService` behind `LocationRepository`) - see
  // `MapExplorationLogic` for the discovery-side copy of these
  // passthroughs. While a mock is live `LocationMonitor` publishes the
  // mocked fix, so every capture here (signboard / stall / additional food)
  // freezes the location AT CAPTURE TIME - one tap on "walk 60 m" is enough
  // to demo the 50 m same-restaurant rule.

  /// Whether this build can mock the OS GPS (Android, non-web).
  bool get mockGpsSupported => repository.location.mockSupported;

  /// Whether a mock is live right now.
  bool get mockGpsActive => repository.location.mockActive;

  /// Teleports the OS GPS to [latitude]/[longitude]. Returns an error
  /// message, or null on success.
  Future<String?> setMockGps({
    required double latitude,
    required double longitude,
  }) => repository.location.setMockLocation(latitude, longitude);

  /// Stops mocking and resumes real GPS fixes.
  Future<void> stopMockGps() => repository.location.stopMockLocation();

  // =========================================================================
  // Continuing an unfinished submission
  // =========================================================================

  /// The saved incomplete submission that THIS capture should ask about
  /// continuing - an unfinished Add-Landmark form whose foods already contain
  /// the SAME dish and [variant] and whose first-food spot is within the
  /// same-restaurant range (50 m) of [captureLocation]. Null when nothing
  /// matches.
  ///
  /// This is what stops "Save & leave" -> back to the camera -> "Add New
  /// Landmark" from silently stacking a SECOND draft of the same visit: the
  /// View asks "continue your unfinished submission?" and reopens this draft
  /// pre-filled when the tourist agrees.
  ///
  /// All three must agree - the dish, the variant and the place. The variant
  /// compares exactly (see [isSameDishAndVariant]): a plain "Cendol" capture
  /// does NOT resume a draft holding "Cendol Jagung" - continuing it would
  /// file the plain dish as that variant - and vice versa. An unknown capture
  /// fix (or a draft without one) can never match either: a draft saved at
  /// another restaurant must not be resumed by a stray capture.
  LandmarkDraft? matchingDraft({
    required List<LandmarkDraft> drafts,
    required LocalFood food,
    required TouristLocation captureLocation,
    String variant = '',
  }) {
    if (drafts.isEmpty || !captureLocation.isKnown) return null;
    for (final LandmarkDraft draft in drafts) {
      if (!draft.baseLocation.isKnown) continue;
      if (!isSameRestaurantCaptureRange(draft.baseLocation, captureLocation)) {
        continue;
      }
      if (!_draftCarriesDish(draft, food, variant)) continue;
      return draft;
    }
    return null;
  }

  /// Whether [draft] already holds [food] WITH the SAME [variant] - one
  /// definition of "the same thing to add" for both the continue ask and the
  /// form's duplicate guard ([isSameDishAndVariant]), so the two rules can
  /// never drift apart.
  bool _draftCarriesDish(LandmarkDraft draft, LocalFood food, String variant) {
    for (final LandmarkDraftFood entry in draft.foods) {
      if (isSameDishAndVariant(entry.food, entry.variant, food, variant)) {
        return true;
      }
    }
    return false;
  }

  /// Whether [candidate] (with [candidateVariant]) is the SAME thing to add
  /// as [existing] (with [existingVariant]) - see
  /// [sameDishAndVariantIdentity], the name/id-level rule this wraps for
  /// [LocalFood]s.
  bool isSameDishAndVariant(
    LocalFood existing,
    String existingVariant,
    LocalFood candidate,
    String candidateVariant,
  ) => sameDishAndVariantIdentity(
    dish: existing.name,
    localFoodId: existing.id,
    variant: existingVariant,
    otherDish: candidate.name,
    otherLocalFoodId: candidate.id,
    otherVariant: candidateVariant,
  );

  /// The saved incomplete submission for the SAME RESTAURANT as a form the
  /// tourist just confirmed - a draft whose restaurant name matches
  /// ([placeNameKey]: trimmed, case- and script-folded) AND whose FIRST-food
  /// capture spot is within [restaurantFormMergeRangeMetres] (100 m) of the
  /// form's own first-food spot. Null when nothing matches, or when either
  /// side has no name / no fix to compare.
  ///
  /// The form's Confirm action asks about combining the two, so one
  /// restaurant keeps ONE unfinished submission instead of two.
  LandmarkDraft? matchingDraftForRestaurant({
    required List<LandmarkDraft> drafts,
    required String restaurantName,
    required TouristLocation formLocation,
    int excludeDraftId = 0,
  }) {
    final String wanted = placeNameKey(restaurantName);
    if (wanted.isEmpty || !formLocation.isKnown) return null;
    for (final LandmarkDraft draft in drafts) {
      // A form continuing its own submission never matches itself - it may
      // only combine with ANOTHER draft of the same restaurant.
      if (excludeDraftId != 0 && draft.id == excludeDraftId) continue;
      if (placeNameKey(draft.restaurantName) != wanted) continue;
      if (!draft.baseLocation.isKnown) continue;
      if (distanceMetres(draft.baseLocation, formLocation) >
          restaurantFormMergeRangeMetres) {
        continue;
      }
      return draft;
    }
    return null;
  }

  /// The ONE "is this the same thing to add?" rule, for callers that hold a
  /// dish as its name + catalogue id + variant. Three places go through it,
  /// so none of them can drift apart:
  ///
  ///   * the Add-Landmark form's duplicate guard (one form cannot hold the
  ///     same dish + variant twice - [isSameDishAndVariant]);
  ///   * the continue ask ([matchingDraft]) - only the very same dish +
  ///     variant resumes a saved form;
  ///   * the A13 attach dedupe ([addFoodsToSubmittedLandmark]) - a landmark
  ///     holding "Cendol Jagung" does NOT already have plain "Cendol".
  ///
  /// The DISH matches by catalogue id when both sides have one, else by
  /// script-folded name (海天樓麵 and 海天楼面 are one dish). The VARIANT must
  /// match too, compared the same way - case and punctuation never split it,
  /// and an empty variant equals an EMPTY variant only.
  static bool sameDishAndVariantIdentity({
    required String dish,
    required int localFoodId,
    required String variant,
    required String otherDish,
    required int otherLocalFoodId,
    required String otherVariant,
  }) {
    final bool sameDish =
        (localFoodId != 0 && localFoodId == otherLocalFoodId) ||
        FoodNameMatcher.normalize(dish) == FoodNameMatcher.normalize(otherDish);
    if (!sameDish) return false;
    return FoodNameMatcher.normalize(variant) ==
        FoodNameMatcher.normalize(otherVariant);
  }
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
