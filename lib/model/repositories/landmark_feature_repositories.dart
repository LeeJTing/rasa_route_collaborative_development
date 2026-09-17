import 'dart:async';

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../data_models/place_photo_match_response.dart';
import '../data_models/signboard_analysis_response.dart';
import '../data_models/signboard_name_match_response.dart';
import '../data_models/signboard_script_check_response.dart';
import '../data_models/stall_analysis_response.dart';
import 'auth_repository.dart';
import 'dietary_restriction_repository.dart';
import 'location_repository.dart';
import 'recognition_repository.dart';
import 'restaurant_repository.dart';
import 'submitted_landmark_repository.dart';

/// Submission-specific persistence adapters.
///
/// Each adapter is composed over the established repository implementation and
/// exposes only the operations needed by the Landmark submission workflow.
/// This keeps the feature boundary explicit without duplicating query logic.
class LandmarkSubmissionRepository {
  final SubmittedLandmarkRepository _source = SubmittedLandmarkRepository();

  Future<int> save(SubmittedLandmark value) => _source.save(value);

  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) =>
      _source.getSubmittedLandmarkById(landmarkId);

  Future<List<SubmittedLandmark>> findByName(String name) =>
      _source.findByName(name);

  Future<List<SubmittedLandmark>> findNearby({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) => _source.findNearby(
    latitude: latitude,
    longitude: longitude,
    maximumDistanceKm: maximumDistanceKm,
  );

  Future<List<SubmittedLandmark>> getSubmittedLandmarksByTourist(
    String touristId,
  ) => _source.getSubmittedLandmarksByTourist(touristId);

  Future<({String id, String url})> uploadImage(List<int> bytes) =>
      _source.uploadImage(bytes);

  Future<void> updateContactFields(
    int landmarkId, {
    String? phone,
    String? website,
    String? address,
  }) => _source.updateContactFields(
    landmarkId,
    phone: phone,
    website: website,
    address: address,
  );

  Future<void> updateLandmarkAddress(
    int landmarkId,
    String address, {
    double? latitude,
    double? longitude,
  }) => _source.updateLandmarkAddress(
    landmarkId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> updateOpeningHoursOnMerge(
    int landmarkId,
    Map<Weekday, List<OpeningHour>> submitted,
  ) => _source.updateOpeningHoursOnMerge(landmarkId, submitted);

  Future<void> addItems(int landmarkId, List<LandmarkItem> items) =>
      _source.addItems(landmarkId, items);

  Future<void> linkItemToFood(
    int landmarkId,
    String dishName,
    int localFoodId,
  ) => _source.linkItemToFood(landmarkId, dishName, localFoodId);

  Future<void> clearReportsAndReactivate(int landmarkId) =>
      _source.clearReportsAndReactivate(landmarkId);
}

class LandmarkLocationRepository {
  final LocationRepository _source = LocationRepository();

  Future<TouristLocation> currentLocation() => _source.currentLocation();

  Stream<TouristLocation> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) => _source.locationStream(interval: interval);

  Future<bool> ensureLocationPermission() => _source.ensureLocationPermission();

  Stream<bool> locationServiceStream() => _source.locationServiceStream();

  bool get mockSupported => _source.mockSupported;
  bool get mockActive => _source.mockActive;
  TouristLocation? get mockLocation => _source.mockLocation;
  Stream<bool> mockActiveChanges() => _source.mockActiveChanges();

  Future<String?> setMockLocation(double latitude, double longitude) =>
      _source.setMockLocation(latitude, longitude);

  Future<void> stopMockLocation() => _source.stopMockLocation();
}

class LandmarkRestaurantRepository {
  final RestaurantRepository _source = RestaurantRepository();

  Future<Restaurant?> findByName(String name) => _source.findByName(name);

  Future<List<Restaurant>> findByNameList(String name) =>
      _source.findByNameList(name);

  Future<List<Restaurant>> getRestaurantsNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) => _source.getRestaurantsNear(
    latitude: latitude,
    longitude: longitude,
    maximumDistanceKm: maximumDistanceKm,
  );

  Future<List<RestaurantItem>> getReportableItems(int restaurantId) =>
      _source.getReportableItems(restaurantId);

  Future<List<RestaurantItem>> getRestaurantItemsByRestaurantIds(
    List<int> restaurantIds,
  ) => _source.getRestaurantItemsByRestaurantIds(restaurantIds);

  Future<void> addRestaurantItem({
    required int restaurantId,
    required int localFoodId,
    required String name,
    String? ingredients,
    String? foodImgUrl,
    String? foodCategory,
    double? price,
  }) => _source.addRestaurantItem(
    restaurantId: restaurantId,
    localFoodId: localFoodId,
    name: name,
    ingredients: ingredients,
    foodImgUrl: foodImgUrl,
    foodCategory: foodCategory,
    price: price,
  );

  Future<void> resetRestaurantModeration(int restaurantId) =>
      _source.resetRestaurantModeration(restaurantId);

  Future<void> updateRestaurantAddress(
    int restaurantId,
    String address, {
    double? latitude,
    double? longitude,
  }) => _source.updateRestaurantAddress(
    restaurantId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> updateRestaurantContactFields(
    int restaurantId, {
    String? phone,
    String? website,
  }) => _source.updateRestaurantContactFields(
    restaurantId,
    phone: phone,
    website: website,
  );

  Future<void> replaceRestaurantOpeningHourDay(
    int restaurantId,
    Weekday day,
    List<OpeningHour> rows,
  ) => _source.replaceRestaurantOpeningHourDay(restaurantId, day, rows);
}

class LandmarkRecognitionRepository {
  final RecognitionRepository _source = RecognitionRepository();

  Future<SignboardAnalysisResponse> analyzeSignboard(List<int> imageBytes) =>
      _source.analyzeSignboard(imageBytes);

  Future<StallAnalysisResponse> analyzeStall(List<int> imageBytes) =>
      _source.analyzeStall(imageBytes);

  Future<SignboardNameMatchResponse> verifySignboardName({
    required List<int> imageBytes,
    required String typedName,
  }) =>
      _source.verifySignboardName(imageBytes: imageBytes, typedName: typedName);

  Future<SignboardScriptCheckResponse> verifySignboardScript({
    required List<int> imageBytes,
  }) => _source.verifySignboardScript(imageBytes: imageBytes);

  Future<PlacePhotoMatchResponse> comparePlacePhotos({
    required List<int> imageBytes,
    required List<int> otherImageBytes,
  }) => _source.comparePlacePhotos(
    imageBytes: imageBytes,
    otherImageBytes: otherImageBytes,
  );
}

class LandmarkIdentityRepository {
  final AuthRepository _source = AuthRepository();

  Future<String?> currentTouristId() => _source.currentTouristId();
}

class LandmarkDietaryRepository {
  final DietaryRestrictionRepository _source = DietaryRestrictionRepository();

  Future<List<DietaryRestriction>> restrictionsForCurrentTourist() =>
      _source.restrictionsForCurrentTourist();

  Future<Map<int, List<int>>> restrictionIdsByFood() =>
      _source.restrictionIdsByFood();
}
