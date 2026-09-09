import 'package:meta/meta.dart' show protected;

import '../../domain_model/food_recognition_result.dart';
import '../../domain_model/landmark_report_reason.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import 'food_recognition_logic.dart';
import 'landmark_submission_logic.dart';

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

  // ===========================================================================
  // Food recognition, re-exposed (from FoodRecognitionLogic)
  // ===========================================================================

  Future<FoodRecognitionResult> recognizeFood(List<int> imageBytes) =>
      foodRecognition.recognizeFood(imageBytes);

  Future<
    ({
      LocalFood food,
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

  String? validateOperatingHours(
    Map<Weekday, List<OpeningHour>> operatingHours,
  ) => submission.validateOperatingHours(operatingHours);

  bool isValidPrice(double price) => submission.isValidPrice(price);

  String? suggestedPriceWarning(
    String foodName,
    double price,
    double priceMin,
    double priceMax,
  ) => submission.suggestedPriceWarning(foodName, price, priceMin, priceMax);

  bool isWithinAllowedRange(
    TouristLocation current,
    double adjustedLat,
    double adjustedLon,
  ) => submission.isWithinAllowedRange(current, adjustedLat, adjustedLon);

  bool isWithinMalaysia(double latitude, double longitude) =>
      submission.isWithinMalaysia(latitude, longitude);

  bool isOnLand(double latitude, double longitude) =>
      submission.isOnLand(latitude, longitude);

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
          // A brand-new landmark took every dish - nothing pre-existed.
          return result.copyWith(
            addedDishNames: <String>[
              for (final FoodSubmission entry in foods)
                if (!entry.isFake) entry.food.name,
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

  /// Records a tourist's report against a submitted landmark (the report
  /// sheet on the landmark detail page) - sign-in required, dedupe per
  /// tourist, count bump, freeze once it passes the threshold; `frozePlace`
  /// is true when this report froze the landmark. Flat passthrough to the
  /// submission logic.
  Future<({bool requiresSignIn, bool alreadyReported, bool frozePlace})>
  submitLandmarkReport({
    required int landmarkId,
    required LandmarkReportReason reason,
    String? touristId,
  }) => submission.submitLandmarkReport(
    landmarkId: landmarkId,
    reason: reason,
    touristId: touristId,
  );
}
