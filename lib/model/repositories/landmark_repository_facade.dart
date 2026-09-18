import 'dart:async';

import '../../domain_model/address_suggestion.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/landmark_draft.dart';
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

import 'geocoding_repository.dart';
import 'landmark_feature_repositories.dart';
import 'landmark_draft_repository.dart';
import 'link_check_repository.dart';

/// REPOSITORY FACADE - a business-logic class holds ONE of these, not six
/// separate repositories. It groups the repositories for one subject area and
/// re-exposes intention-shaped operations as a single flat API. Its concrete
/// repositories stay private so business logic cannot bypass the boundary.
class LandmarkRepositoryFacade {
  LandmarkRepositoryFacade();

  final LandmarkSubmissionRepository _landmark = LandmarkSubmissionRepository();
  final LandmarkLocationRepository _location = LandmarkLocationRepository();
  final LandmarkRestaurantRepository _restaurant =
      LandmarkRestaurantRepository();
  final LandmarkRecognitionRepository _recognition =
      LandmarkRecognitionRepository();
  final LandmarkIdentityRepository _auth = LandmarkIdentityRepository();

  /// Website reachability checks for the Add-Landmark website field.
  final LinkCheckRepository _links = LinkCheckRepository();

  /// OpenStreetMap geocoding for the Add-Landmark address field (suggestions)
  /// and the composed address behind the map pin.
  final GeocodingRepository _geocoding = GeocodingRepository();

  /// Saved (incomplete) Add-New-Landmark forms.
  final LandmarkDraftRepository _drafts = LandmarkDraftRepository();

  final LandmarkDietaryRepository _dietaryRestriction =
      LandmarkDietaryRepository();

  Future<List<DietaryRestriction>> getCurrentDietaryRestrictions() =>
      _dietaryRestriction.restrictionsForCurrentTourist();

  Future<Map<int, List<int>>> getRestrictionIdsByFood() =>
      _dietaryRestriction.restrictionIdsByFood();

  // -------------------------------------------------------------------------
  // Authentication and landmark drafts
  // -------------------------------------------------------------------------

  Future<String?> currentTouristId() => _auth.currentTouristId();

  Future<int> saveDraft({
    required String touristId,
    required LandmarkDraft draft,
  }) => _drafts.save(touristId: touristId, draft: draft);

  Future<List<LandmarkDraft>> draftsByTourist(String touristId) =>
      _drafts.draftsByTourist(touristId);

  Future<void> deleteDraft(LandmarkDraft draft) => _drafts.deleteDraft(draft);

  Future<void> deleteDraftRow(int draftId) => _drafts.deleteDraftRow(draftId);

  Future<void> deleteDraftPhoto(String objectId) =>
      _drafts.deletePhoto(objectId);

  // -------------------------------------------------------------------------
  // Device location
  // -------------------------------------------------------------------------

  Future<TouristLocation> currentLocation() => _location.currentLocation();

  Stream<TouristLocation> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) => _location.locationStream(interval: interval);

  Future<bool> ensureLocationPermission() =>
      _location.ensureLocationPermission();

  Stream<bool> locationServiceStream() => _location.locationServiceStream();

  bool get mockLocationSupported => _location.mockSupported;

  bool get mockLocationActive => _location.mockActive;

  TouristLocation? get activeMockLocation => _location.mockLocation;

  Stream<bool> mockLocationActiveChanges() => _location.mockActiveChanges();

  Future<String?> setMockLocation(double latitude, double longitude) =>
      _location.setMockLocation(latitude, longitude);

  Future<void> stopMockLocation() => _location.stopMockLocation();

  // -------------------------------------------------------------------------
  // Address and link services
  // -------------------------------------------------------------------------

  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => _geocoding.searchAddresses(query: query, around: around);

  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      _geocoding.reverseGeocodeAddress(location);

  Future<bool> isWebsiteReachable(String url) => _links.isWebsiteReachable(url);

  Future<List<int>?> fetchImageBytes(String url) => _links.fetchImageBytes(url);

  Future<SignboardAnalysisResponse> analyzeSignboard(List<int> imageBytes) =>
      _recognition.analyzeSignboard(imageBytes);

  Future<StallAnalysisResponse> analyzeStall(List<int> imageBytes) =>
      _recognition.analyzeStall(imageBytes);

  Future<SignboardNameMatchResponse> verifySignboardName({
    required List<int> imageBytes,
    required String typedName,
  }) => _recognition.verifySignboardName(
    imageBytes: imageBytes,
    typedName: typedName,
  );

  Future<SignboardScriptCheckResponse> verifySignboardScript({
    required List<int> imageBytes,
  }) => _recognition.verifySignboardScript(imageBytes: imageBytes);

  Future<PlacePhotoMatchResponse> comparePlacePhotos({
    required List<int> imageBytes,
    required List<int> otherImageBytes,
  }) => _recognition.comparePlacePhotos(
    imageBytes: imageBytes,
    otherImageBytes: otherImageBytes,
  );

  Future<Restaurant?> findRestaurantByName(String name) =>
      _restaurant.findByName(name);

  Future<List<Restaurant>> restaurantsByName(String name) =>
      _restaurant.findByNameList(name);

  Future<List<Restaurant>> restaurantsNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) => _restaurant.getRestaurantsNear(
    latitude: latitude,
    longitude: longitude,
    maximumDistanceKm: maximumDistanceKm,
  );

  Future<List<RestaurantItem>> restaurantReportableItems(int restaurantId) =>
      _restaurant.getReportableItems(restaurantId);

  Future<List<RestaurantItem>> restaurantItemsForIds(List<int> restaurantIds) =>
      _restaurant.getRestaurantItemsByRestaurantIds(restaurantIds);

  Future<void> addRestaurantItem({
    required int restaurantId,
    required int localFoodId,
    required String name,
    String? ingredients,
    String? foodImgUrl,
    String? foodCategory,
    double? price,
  }) => _restaurant.addRestaurantItem(
    restaurantId: restaurantId,
    localFoodId: localFoodId,
    name: name,
    ingredients: ingredients,
    foodImgUrl: foodImgUrl,
    foodCategory: foodCategory,
    price: price,
  );

  Future<void> resetRestaurantModeration(int restaurantId) =>
      _restaurant.resetRestaurantModeration(restaurantId);

  Future<void> updateRestaurantAddress(
    int restaurantId,
    String address, {
    double? latitude,
    double? longitude,
  }) => _restaurant.updateRestaurantAddress(
    restaurantId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> updateRestaurantContactFields(
    int restaurantId, {
    String? phone,
    String? website,
  }) => _restaurant.updateRestaurantContactFields(
    restaurantId,
    phone: phone,
    website: website,
  );

  Future<void> replaceRestaurantOpeningHourDay(
    int restaurantId,
    Weekday day,
    List<OpeningHour> rows,
  ) => _restaurant.replaceRestaurantOpeningHourDay(restaurantId, day, rows);

  Future<int> saveLandmark(SubmittedLandmark value) => _landmark.save(value);

  Future<SubmittedLandmark?> submittedLandmarkById(int landmarkId) =>
      _landmark.getSubmittedLandmarkById(landmarkId);

  Future<List<SubmittedLandmark>> landmarksByName(String name) =>
      _landmark.findByName(name);

  Future<List<SubmittedLandmark>> landmarksNear({
    required double latitude,
    required double longitude,
    required double maximumDistanceKm,
  }) => _landmark.findNearby(
    latitude: latitude,
    longitude: longitude,
    maximumDistanceKm: maximumDistanceKm,
  );

  Future<List<SubmittedLandmark>> submittedLandmarksByTourist(
    String touristId,
  ) => _landmark.getSubmittedLandmarksByTourist(touristId);

  Future<({String id, String url})> uploadLandmarkImage(List<int> bytes) =>
      _landmark.uploadImage(bytes);

  Future<void> updateLandmarkContactFields(
    int landmarkId, {
    String? phone,
    String? website,
    String? address,
  }) => _landmark.updateContactFields(
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
  }) => _landmark.updateLandmarkAddress(
    landmarkId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> updateLandmarkOpeningHours(
    int landmarkId,
    Map<Weekday, List<OpeningHour>> submitted,
  ) => _landmark.updateOpeningHoursOnMerge(landmarkId, submitted);

  Future<void> addLandmarkItems(int landmarkId, List<LandmarkItem> items) =>
      _landmark.addItems(landmarkId, items);

  Future<void> linkLandmarkItemToFood(
    int landmarkId,
    String dishName,
    int localFoodId,
  ) => _landmark.linkItemToFood(landmarkId, dishName, localFoodId);

  Future<void> clearLandmarkReportsAndReactivate(int landmarkId) =>
      _landmark.clearReportsAndReactivate(landmarkId);
}
