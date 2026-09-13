import 'package:meta/meta.dart' show protected;

import '../../domain_model/address_suggestion.dart';
import '../../domain_model/food_recognition_result.dart';
import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import 'food_recognition_logic.dart';
import 'landmark_draft_logic.dart';
import 'landmark_submission_logic.dart';
import 'opening_hours_logic.dart';

/// Contributing a food landmark - recognising the dish, capturing the
/// restaurant, submitting it. Used by the FoodRecognition, LandmarkDetail,
/// AddLandmark and LandmarkHistory ViewModels.
///
/// The dashboard map is **not** here: `MapExplorationLogic` belongs to
/// `DiscoveryLogicFacade`, which is the one facade `DashboardViewModel` talks
/// to. A logic class lives in exactly one logic facade.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. Behind it the
/// facade fans out to as many business-logic classes as the feature needs. No
/// business rules live here, and it never imports Flutter.
///
/// A ViewModel calls the flat methods on this facade, never
/// `facade.submission.xxx` or `facade.foodRecognition.xxx` - the same rule
/// `DiscoveryLogicFacade` documents for `DashboardViewModel` (which calls
/// `discoveryLogic.foodDistribution(...)`, never
/// `discoveryLogic.mapExploration.distribution(...)`).
class LandmarkLogicFacade {
  LandmarkLogicFacade();

  @protected
  FoodRecognitionLogic createFoodRecognition() => FoodRecognitionLogic();

  late final FoodRecognitionLogic foodRecognition = createFoodRecognition();
  final LandmarkSubmissionLogic submission = LandmarkSubmissionLogic();
  final LandmarkDraftLogic draftLogic = LandmarkDraftLogic();

  // ===========================================================================
  // Food recognition, re-exposed (from FoodRecognitionLogic)
  // ===========================================================================

  Future<FoodRecognitionResult> recognizeFood(List<int> imageBytes) =>
      foodRecognition.recognizeFood(imageBytes);

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
  resolveByName(List<int> imageBytes, String name) =>
      foodRecognition.resolveByName(imageBytes, name);

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
  enrichCandidate(List<int> imageBytes, String name) =>
      foodRecognition.enrichCandidate(imageBytes, name);

  bool isLowConfidence(double confidence) =>
      foodRecognition.isLowConfidence(confidence);

  Future<bool> requestCameraPermission() =>
      foodRecognition.requestCameraPermission();

  /// The signed-in tourist's dietary restriction names (e.g. "No Pork"), used
  /// to warn when a recognised dish conflicts with their profile - see
  /// `FoodRecognitionLogic.userDietaryRestrictionNames`.
  Future<List<String>> userDietaryRestrictions() =>
      foodRecognition.userDietaryRestrictionNames();

  /// Of [userRestrictions], the ones [foodTags] conflict with - pure match,
  /// no I/O (see `FoodRecognitionLogic.dietaryConflicts`).
  List<String> dietaryConflicts({
    required List<String> userRestrictions,
    required List<String> foodTags,
  }) => FoodRecognitionLogic.dietaryConflicts(
    userRestrictions: userRestrictions,
    foodTags: foodTags,
  );

  // ===========================================================================
  // Landmark submission, re-exposed (from LandmarkSubmissionLogic)
  // ===========================================================================

  Future<String> analyzeSignboard(List<int> imageBytes) =>
      submission.analyzeSignboard(imageBytes);

  Future<void> analyzeStall(List<int> imageBytes) =>
      submission.analyzeStall(imageBytes);

  Future<String?> currentTouristId() => submission.currentTouristId();

  /// One submitted landmark (with its dishes and opening hours) for the
  /// detail screen - flat passthrough to the submission logic.
  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) =>
      submission.getSubmittedLandmarkById(landmarkId);

  /// Every submitted landmark the tourist has contributed dishes to, newest
  /// first - flat passthrough to the submission logic.
  Future<List<SubmittedLandmark>> getSubmittedLandmarksByTourist(
    String touristId,
  ) => submission.getSubmittedLandmarksByTourist(touristId);

  Future<({String id, String url})> uploadImage(List<int> bytes) =>
      submission.uploadImage(bytes);

  bool isValidTimeOrder(int opensAt, int closesAt) =>
      submission.isValidTimeOrder(opensAt, closesAt);

  /// The encoded close for an edited opening-hours row: a closing time at or
  /// before the opening time means the NEXT day - "10:00 -> 02:00" becomes
  /// `600 -> 1560` (minutes past midnight + 1440). See
  /// `OpeningHoursLogic.encodeClose` / `OpeningHoursRows`.
  int encodeCloseTime({required int opensAt, required int closeMinutes}) =>
      OpeningHoursLogic.encodeClose(
        opensAt: opensAt,
        closeMinutes: closeMinutes,
      );

  String? validateOperatingHours(
    Map<Weekday, List<OpeningHour>> operatingHours,
  ) => submission.validateOperatingHours(operatingHours);

  bool isValidPrice(double price) => submission.isValidPrice(price);

  /// The food-price band (see `LandmarkSubmissionLogic.minPrice` /
  /// [maxPrice]) - 0.01 to 9999.99 MYR.
  double get minPrice => LandmarkSubmissionLogic.minPrice;
  double get maxPrice => LandmarkSubmissionLogic.maxPrice;

  /// The price field's digit shape (4 integral digits, 2 decimals).
  int get priceIntegralDigits => LandmarkSubmissionLogic.priceIntegralDigits;
  int get priceDecimalDigits => LandmarkSubmissionLogic.priceDecimalDigits;

  /// The price text as shown while typing - a leading zero is rewritten to
  /// the value's two-decimal form (see
  /// `LandmarkSubmissionLogic.normalisePriceEntryText`).
  String normalisePriceEntryText(String text) =>
      LandmarkSubmissionLogic.normalisePriceEntryText(text);

  /// The price text as shown once the field is left - always two decimals
  /// (see `LandmarkSubmissionLogic.formatPriceText`).
  String formatPriceText(String text) =>
      LandmarkSubmissionLogic.formatPriceText(text);

  String? suggestedPriceWarning(
    String foodName,
    double price,
    double priceMin,
    double priceMax,
  ) => submission.suggestedPriceWarning(foodName, price, priceMin, priceMax);

  /// The suggested range as an informational display line ("Suggested price:
  /// RM 2.00 - RM 8.00") - see
  /// [LandmarkSubmissionLogic.suggestedPriceRangeText].
  String? suggestedPriceRangeText(double priceMin, double priceMax) =>
      submission.suggestedPriceRangeText(priceMin, priceMax);

  bool isWithinAllowedRange(
    TouristLocation current,
    double adjustedLat,
    double adjustedLon,
  ) => submission.isWithinAllowedRange(current, adjustedLat, adjustedLon);

  /// The pin correction allowance for the FORM's own copy (warning text) -
  /// see `LandmarkSubmissionLogic.pinAdjustmentRangeMetres` (100 m).
  double get pinAdjustmentRangeMetres =>
      LandmarkSubmissionLogic.pinAdjustmentRangeMetres;

  bool isWithinMalaysia(double latitude, double longitude) =>
      submission.isWithinMalaysia(latitude, longitude);

  bool isOnLand(double latitude, double longitude) =>
      submission.isOnLand(latitude, longitude);

  /// Shortest allowed single opening-hours row, in minutes - see
  /// `LandmarkSubmissionLogic.minimumOperatingRowMinutes`.
  int get minimumOpeningRowMinutes =>
      LandmarkSubmissionLogic.minimumOperatingRowMinutes;

  /// Haversine distance between two fixes, in metres.
  double distanceMetres(TouristLocation a, TouristLocation b) =>
      submission.distanceMetres(a, b);

  /// Whether a later capture (additional food / signboard / stall) is close
  /// enough to the first captured food to belong to the same restaurant -
  /// see `LandmarkSubmissionLogic.isSameRestaurantCaptureRange`.
  bool isSameRestaurantCaptureRange(
    TouristLocation firstFoodLocation,
    TouristLocation captured,
  ) => submission.isSameRestaurantCaptureRange(firstFoodLocation, captured);

  /// Message shown when a capture is too far from the first captured food.
  String captureTooFarMessage(String capturedWhat) =>
      submission.captureTooFarMessage(capturedWhat);

  // ===========================================================================
  // Incomplete landmark drafts, re-exposed (from LandmarkDraftLogic)
  // ===========================================================================

  /// How long a saved draft stays resumable after its last save (24 hours).
  Duration get landmarkDraftLifetime => LandmarkDraftLogic.draftLifetime;

  /// Saves (or updates, when [draft] already has an id) an incomplete
  /// Add-New-Landmark form for the signed-in tourist. Returns the draft id,
  /// or 0 when nobody is signed in.
  Future<int> saveLandmarkDraft(LandmarkDraft draft) =>
      draftLogic.saveDraft(draft);

  /// The signed-in tourist's resumable drafts, newest first. Expired drafts
  /// are deleted on the way (row + photos).
  Future<List<LandmarkDraft>> pendingLandmarkDrafts() =>
      draftLogic.pendingDrafts();

  /// Discards one draft - the tourist chose not to continue it.
  Future<void> discardLandmarkDraft(LandmarkDraft draft) =>
      draftLogic.deleteDraft(draft);

  /// Removes a draft row after a successful submission (its photos stay -
  /// the submitted landmark stores them).
  Future<void> clearSubmittedLandmarkDraft(int draftId) =>
      draftLogic.clearSubmittedDraft(draftId);

  /// Deletes one uploaded draft photo by its storage object name (best
  /// effort) - used when a draft photo is replaced by a fresh capture.
  Future<void> discardLandmarkDraftPhoto(String objectId) =>
      draftLogic.deletePhoto(objectId);

  // Add-Landmark contact / address validation (flat passthroughs - the pure
  // rules live in `LandmarkSubmissionLogic`, reachability in the repository).

  bool isValidMalaysianPhone(String phone) =>
      submission.isValidMalaysianPhone(phone);

  /// The fixed country-code prefix the Add-Landmark phone field always shows
  /// as plain, non-editable text (see
  /// `LandmarkSubmissionLogic.phoneCountryCode`) - display only, the stored
  /// value uses the restaurant table's national format.
  String get phoneCountryCode => LandmarkSubmissionLogic.phoneCountryCode;

  /// The national digits of a stored phone - what the field shows beside the
  /// fixed prefix (see `LandmarkSubmissionLogic.phoneNationalPart`).
  String phoneNationalPart(String phone) =>
      LandmarkSubmissionLogic.phoneNationalPart(phone);

  /// A phone entry in the SAME format the `restaurant` table stores phones
  /// in - see `LandmarkSubmissionLogic.formatMalaysianPhone`.
  String formatMalaysianPhone(String phone) =>
      LandmarkSubmissionLogic.formatMalaysianPhone(phone);

  bool isValidWebsiteFormat(String website) =>
      submission.isValidWebsiteFormat(website);

  bool websiteContainsWhitespace(String website) =>
      submission.websiteContainsWhitespace(website);

  bool websiteContainsMultipleUrls(String website) =>
      submission.websiteContainsMultipleUrls(website);

  /// The user-readable verdict when [error] is the pre-submit origin
  /// verifier's rejection thrown by [submitLandmark] ("...is not recognised
  /// as a Malaysian local food"), else null. Lets the form re-surface that
  /// deliberate message without importing logic classes or dumping raw
  /// error text.
  String? landmarkVerificationRejectionMessage(Object error) =>
      error is LandmarkVerificationRejectedException ? error.message : null;

  bool isValidAddressText(String address) =>
      submission.isValidAddressText(address);

  /// The granular address rules behind [isValidAddressText], so the form can
  /// say exactly what is wrong (see
  /// `LandmarkSubmissionLogic.addressHasAllowedCharacters` and friends).
  bool addressHasAllowedCharacters(String address) =>
      submission.addressHasAllowedCharacters(address);

  bool addressStartsOrEndsWithSpecialChar(String address) =>
      submission.addressStartsOrEndsWithSpecialChar(address);

  bool addressHasRepeatedSpecialChar(String address) =>
      submission.addressHasRepeatedSpecialChar(address);

  bool addressContainsLetter(String address) =>
      submission.addressContainsLetter(address);

  bool addressContainsDigit(String address) =>
      submission.addressContainsDigit(address);

  /// The shortest acceptable address (see
  /// `LandmarkSubmissionLogic.minAddressLength`).
  int get minAddressLength => LandmarkSubmissionLogic.minAddressLength;

  /// The shortest typed query that triggers address suggestions (see
  /// `LandmarkSubmissionLogic.minAddressSearchLength`).
  int get minAddressSearchLength =>
      LandmarkSubmissionLogic.minAddressSearchLength;

  /// Live OpenStreetMap address suggestions for the form's address field,
  /// measured from [around] and sorted nearest-first. `null` = the lookup
  /// failed; empty = nothing matched (see
  /// `LandmarkSubmissionLogic.searchAddresses`).
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => submission.searchAddresses(query: query, around: around);

  /// The composed OpenStreetMap address of one point, in the DB style the
  /// address field expects - `null` when OSM has nothing usable there (see
  /// `LandmarkSubmissionLogic.reverseGeocodeAddress`).
  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      submission.reverseGeocodeAddress(location);

  /// How the form labels a suggestion's distance ("350 m", "1.2 km").
  String formatDistance(double metres) => submission.formatDistance(metres);

  bool isValidRestaurantNameText(String name) =>
      submission.isValidRestaurantNameText(name);

  bool containsControlCharacters(String value) =>
      submission.containsControlCharacters(value);

  /// Add-Landmark field caps (mirrored in the View as TextField maxLength).
  int get maxRestaurantNameLength =>
      LandmarkSubmissionLogic.maxRestaurantNameLength;
  int get maxPhoneLength => LandmarkSubmissionLogic.maxPhoneLength;
  int get maxWebsiteLength => LandmarkSubmissionLogic.maxWebsiteLength;

  /// How close to the website cap the amber "stay under" warning starts
  /// (2043 of 2048) - advisory only, it never blocks submission.
  int get websiteWarnFromLength =>
      LandmarkSubmissionLogic.websiteWarnFromLength;
  int get maxAddressLength => LandmarkSubmissionLogic.maxAddressLength;

  /// Manual food-name entry cap + amber warning rule, shared by BOTH
  /// recognition-screen name fields (the single-result card's "type the
  /// name" and the multiple-results fallback) - see
  /// `LandmarkSubmissionLogic.foodNameLengthWarning`.
  int get maxFoodNameLength => LandmarkSubmissionLogic.maxFoodNameLength;
  String? foodNameLengthWarning(String foodName) =>
      submission.foodNameLengthWarning(foodName);

  /// How close to the restaurant-name cap the amber "stay under" warning
  /// starts (91 of 100) - advisory only, like the website one; a name AT the
  /// cap is still submittable.
  int get restaurantNameWarnFromLength =>
      LandmarkSubmissionLogic.restaurantNameWarnFromLength;

  /// The price band as the form's messages word it ("RM0.01 and
  /// RM9,999.99") - see `LandmarkSubmissionLogic.priceBandRangeText`.
  String get priceBandRangeText => LandmarkSubmissionLogic.priceBandRangeText;

  /// Copy for a merged submit (A13) - see
  /// `LandmarkSubmissionLogic.mergeConfirmation`.
  String mergeConfirmation({
    required String targetName,
    required List<String> addedDishNames,
    required List<String> existingDishNames,
  }) => LandmarkSubmissionLogic.mergeConfirmation(
    targetName: targetName,
    addedDishNames: addedDishNames,
    existingDishNames: existingDishNames,
  );

  Future<bool> isWebsiteReachable(String url) =>
      submission.isWebsiteReachable(url);

  // Dev GPS mock passthroughs (presenter tool). The SAME singleton the
  // dashboard drives, so a mock set on one screen is live on the other.

  bool get mockGpsSupported => submission.mockGpsSupported;
  bool get mockGpsActive => submission.mockGpsActive;

  Future<String?> setMockGps({
    required double latitude,
    required double longitude,
  }) => submission.setMockGps(latitude: latitude, longitude: longitude);

  Future<void> stopMockGps() => submission.stopMockGps();

  /// The unfinished submission a capture should ask about CONTINUING -
  /// matched by dish, variant AND spot (50 m). See
  /// `LandmarkSubmissionLogic.matchingDraft`.
  LandmarkDraft? matchingLandmarkDraft({
    required List<LandmarkDraft> drafts,
    required LocalFood food,
    required TouristLocation captureLocation,
    String variant = '',
  }) => submission.matchingDraft(
    drafts: drafts,
    food: food,
    captureLocation: captureLocation,
    variant: variant,
  );

  /// Whether the candidate dish+variant is already on the form - see
  /// [LandmarkSubmissionLogic.isSameDishAndVariant].
  bool isSameDishAndVariant(
    LocalFood existing,
    String existingVariant,
    LocalFood candidate,
    String candidateVariant,
  ) => submission.isSameDishAndVariant(
    existing,
    existingVariant,
    candidate,
    candidateVariant,
  );

  /// The one-line notice for a duplicate dish - shared by the capture
  /// screen's blocking message and the form's snackbar (see
  /// `LandmarkSubmissionLogic.duplicateFoodNotice`).
  String get duplicateFoodNotice => LandmarkSubmissionLogic.duplicateFoodNotice;

  /// The name to report for a dish - its VARIANT when one was recorded, else
  /// the dictionary name (see [LandmarkSubmissionLogic.dishLabel]).
  String dishLabel(String dish, String variant) =>
      LandmarkSubmissionLogic.dishLabel(dish, variant);

  /// The saved incomplete submission for the same RESTAURANT (name + first
  /// spot within 100 m) - the Add-Landmark form's Confirm action asks about
  /// combining the two. See
  /// [LandmarkSubmissionLogic.matchingDraftForRestaurant].
  LandmarkDraft? matchingLandmarkDraftForRestaurant({
    required List<LandmarkDraft> drafts,
    required String restaurantName,
    required TouristLocation formLocation,
    int excludeDraftId = 0,
  }) => submission.matchingDraftForRestaurant(
    drafts: drafts,
    restaurantName: restaurantName,
    formLocation: formLocation,
    excludeDraftId: excludeDraftId,
  );

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
    // Pre-submit gate: a dish that is NOT already a catalogue link must pass
    // the 3-step origin verification BEFORE the landmark is saved. A rejection
    // throws here (before any persistence), so the user sees why and nothing
    // is written.
    await foodRecognition.verifyNewFoodsOrThrow(foods);

    final LandmarkSubmitResult result = await submission.submitLandmark(
      restaurantName: restaurantName,
      latitude: latitude,
      longitude: longitude,
      category: category,
      touristId: touristId,
      imageUrl: imageUrl,
      imageId: imageId,
      imageCategory: imageCategory,
      phone: phone,
      website: website,
      address: address,
      foods: foods,
      operatingHours: operatingHours,
    );
    // Option C - best-effort catalogue growth. The landmark write (or the
    // merge) is the thing the tourist confirmed; a catalogue insert that
    // fails (e.g. the RLS migration not applied yet) must not fail the
    // submission that already succeeded. alreadyVerified: the 3-step gate
    // already ran above. New dishes are registered in EVERY outcome - a
    // merged dish still needs a `local_food` row so it can be attached (both
    // merge targets require a `local_food_id`).
    try {
      final Map<String, int> newFoodIds = await foodRecognition
          .registerNewDishes(foods, alreadyVerified: true);
      switch (result.outcome) {
        case LandmarkSubmitOutcome.created:
          if (result.landmarkId != null && newFoodIds.isNotEmpty) {
            // The new rows' ids were 0 at item-insert time - point the
            // just-saved items at them now, so the map resolves the pins like
            // restaurant pins do.
            await submission.linkNewFoodsToLandmark(
              result.landmarkId!,
              newFoodIds,
            );
          }
          // A brand-new landmark took every dish - nothing pre-existed. A
          // dish is named by its VARIANT when one was captured (that is what
          // the tourist added), else the dictionary name.
          return result.copyWith(
            addedDishNames: <String>[
              for (final FoodSubmission entry in foods)
                if (!entry.isFake)
                  LandmarkSubmissionLogic.dishLabel(
                    entry.food.name,
                    entry.variant,
                  ),
            ],
          );
        case LandmarkSubmitOutcome.mergedIntoRestaurant:
          // A13 - attach the dishes (now with resolved catalogue ids) to the
          // existing restaurant as `restaurant_item` rows. Dishes already
          // listed there come back in `existing` for the "item exists" note.
          final FoodAttachResult attach = await submission.addFoodsToRestaurant(
            result.restaurantId!,
            foods,
            newFoodIds,
          );
          return result.copyWith(
            addedDishNames: attach.added,
            existingDishNames: attach.existing,
          );
        case LandmarkSubmitOutcome.mergedIntoLandmark:
          // Same place is an existing submitted landmark - attach there.
          final FoodAttachResult attach = await submission
              .addFoodsToSubmittedLandmark(
                landmarkId: result.landmarkId!,
                touristId: touristId,
                foods: foods,
                newFoodIds: newFoodIds,
              );
          return result.copyWith(
            addedDishNames: attach.added,
            existingDishNames: attach.existing,
          );
      }
    } catch (_) {
      // Ignored - the landmark/merge was already saved; report the bare
      // outcome without the dish-level detail.
      return result;
    }
  }
}
