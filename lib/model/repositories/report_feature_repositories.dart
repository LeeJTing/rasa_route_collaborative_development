import '../../domain_model/address_suggestion.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import 'auth_repository.dart';
import 'geocoding_repository.dart';
import 'map_repository.dart';
import 'restaurant_repository.dart';
import 'submitted_landmark_repository.dart';

/// Reporting-specific persistence adapters.
///
/// These are deliberately composed adapters rather than empty subclasses.
/// They expose only the operations required by report moderation, preserving
/// the established repository queries and write ordering behind that boundary.
class ReportRestaurantRepository {
  final RestaurantRepository _source = RestaurantRepository();

  Future<List<RestaurantItem>> reportableItems(int restaurantId) =>
      _source.getReportableItems(restaurantId);

  Future<void> replaceOpeningHourDay(
    int restaurantId,
    Weekday day,
    List<OpeningHour> rows,
  ) => _source.replaceRestaurantOpeningHourDay(restaurantId, day, rows);

  Future<void> updateItemPrice(int itemId, double price) =>
      _source.updateRestaurantItemPrice(itemId, price);

  Future<void> softRemoveItem(int itemId) =>
      _source.softRemoveRestaurantItem(itemId);

  Future<int> countVisibleItems(int restaurantId) =>
      _source.countVisibleRestaurantItems(restaurantId);

  Future<void> removePlace(int restaurantId) =>
      _source.removeRestaurant(restaurantId);

  Future<void> updateAddress(
    int restaurantId,
    String address, {
    required double latitude,
    required double longitude,
  }) => _source.updateRestaurantAddress(
    restaurantId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> freezePlace(int restaurantId, {DateTime? closedUntil}) =>
      _source.freezeRestaurant(restaurantId, closedUntil: closedUntil);
}

class ReportLandmarkRepository {
  final SubmittedLandmarkRepository _source = SubmittedLandmarkRepository();

  Future<List<LandmarkItem>> reportableItems(int landmarkId) =>
      _source.getReportableItems(landmarkId);

  Future<void> replaceOpeningHourDay(
    int landmarkId,
    Weekday day,
    List<OpeningHour> rows,
  ) => _source.replaceLandmarkOpeningHourDay(landmarkId, day, rows);

  Future<void> updateItemPrice(int itemId, double price) =>
      _source.updateLandmarkItemPrice(itemId, price);

  Future<void> softRemoveItem(int itemId) =>
      _source.softRemoveLandmarkItem(itemId);

  Future<int> countVisibleItems(int landmarkId) =>
      _source.countVisibleLandmarkItems(landmarkId);

  Future<void> removePlace(int landmarkId) =>
      _source.removeLandmark(landmarkId);

  Future<void> updateAddress(
    int landmarkId,
    String address, {
    required double latitude,
    required double longitude,
  }) => _source.updateLandmarkAddress(
    landmarkId,
    address,
    latitude: latitude,
    longitude: longitude,
  );

  Future<void> freezePlace(int landmarkId, {DateTime? closedUntil}) =>
      _source.freezeLandmark(landmarkId, closedUntil: closedUntil);
}

class ReportIdentityRepository {
  final AuthRepository _source = AuthRepository();

  Future<String?> currentTouristId() => _source.currentTouristId();
}

class ReportMapRepository {
  final MapRepository _source = MapRepository();

  void clearCache() => _source.clearCache();
}

class ReportGeocodingRepository {
  final GeocodingRepository _source = GeocodingRepository();

  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => _source.searchAddresses(query: query, around: around);

  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      _source.reverseGeocodeAddress(location);
}
