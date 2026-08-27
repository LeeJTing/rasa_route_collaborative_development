import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/food_recognition_result.dart';
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
  LandmarkLogicFacade({
    @visibleForTesting FoodRecognitionLogic? foodRecognition,
  }) : foodRecognition = foodRecognition ?? FoodRecognitionLogic();

  final FoodRecognitionLogic foodRecognition;
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
      String observedFood,
    })
  >
  resolveByName(List<int> imageBytes, String name) =>
      foodRecognition.resolveByName(imageBytes, name);

  Future<({LocalFood food, double priceMin, double priceMax})> enrichCandidate(
    List<int> imageBytes,
    String name,
  ) => foodRecognition.enrichCandidate(imageBytes, name);

  bool isLowConfidence(double confidence) =>
      foodRecognition.isLowConfidence(confidence);

  Future<bool> requestCameraPermission() =>
      foodRecognition.requestCameraPermission();

  // ===========================================================================
  // Landmark submission, re-exposed (from LandmarkSubmissionLogic)
  // ===========================================================================

  Future<String> analyzeSignboard(List<int> imageBytes) =>
      submission.analyzeSignboard(imageBytes);

  Future<void> analyzeStall(List<int> imageBytes) =>
      submission.analyzeStall(imageBytes);

  Future<String?> currentTouristId() => submission.currentTouristId();

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

  Future<void> submitLandmark({
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
    await submission.submitLandmark(
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
    // Option C - best-effort catalogue growth. The landmark write is the one
    // the tourist confirmed; a catalogue insert that fails (e.g. the RLS
    // migration not applied yet) must not fail the submission that already
    // succeeded.
    try {
      await foodRecognition.registerNewDishes(foods);
    } catch (_) {
      // Ignored - the landmark was already saved.
    }
  }
}
