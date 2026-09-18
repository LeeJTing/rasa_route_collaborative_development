import 'package:meta/meta.dart' show protected;

import '../../domain_model/address_suggestion.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import 'report_feature_repositories.dart';
import 'report_repository.dart';

/// Repository boundary for the complete report-moderation workflow.
///
/// This facade intentionally delegates to the existing repositories without
/// changing their queries, cache lifetimes, write order, or error behaviour.
/// Reporting business logic therefore describes only the moderation flow and
/// cannot reach concrete repository implementations directly.
class ReportRepositoryFacade {
  ReportRepositoryFacade();

  @protected
  ReportRepository createReportRepository() => ReportRepository();

  @protected
  ReportRestaurantRepository createRestaurantRepository() =>
      ReportRestaurantRepository();

  @protected
  ReportLandmarkRepository createLandmarkRepository() =>
      ReportLandmarkRepository();

  @protected
  ReportIdentityRepository createAuthRepository() => ReportIdentityRepository();

  @protected
  ReportMapRepository createMapRepository() => ReportMapRepository();

  @protected
  ReportGeocodingRepository createGeocodingRepository() =>
      ReportGeocodingRepository();

  late final ReportRepository _report = createReportRepository();
  late final ReportRestaurantRepository _restaurant =
      createRestaurantRepository();
  late final ReportLandmarkRepository _landmark = createLandmarkRepository();
  late final ReportIdentityRepository _auth = createAuthRepository();
  late final ReportMapRepository _map = createMapRepository();
  late final ReportGeocodingRepository _geocoding = createGeocodingRepository();

  Future<String?> currentTouristId() => _auth.currentTouristId();

  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => _geocoding.searchAddresses(query: query, around: around);

  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      _geocoding.reverseGeocodeAddress(location);

  Future<List<ReportableMenuItem>> reportableItemsFor({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) async {
    if (placeKind == ReportPlaceKind.restaurant) {
      final List<RestaurantItem> items = await _restaurant.reportableItems(
        placeId,
      );
      return <ReportableMenuItem>[
        for (final RestaurantItem item in items)
          ReportableMenuItem(
            itemKind: ReportItemKind.restaurantItem,
            id: item.id,
            name: item.foodName,
            price: item.price,
            isRemoved: item.isRemoved,
          ),
      ];
    }

    final List<LandmarkItem> items = await _landmark.reportableItems(placeId);
    return <ReportableMenuItem>[
      for (final LandmarkItem item in items)
        ReportableMenuItem(
          itemKind: ReportItemKind.landmarkItem,
          id: item.id,
          name: item.displayName,
          price: item.price,
          isRemoved: item.isRemoved,
        ),
    ];
  }

  Future<bool> alreadyReported({
    required ReportClaim claim,
    required String touristId,
  }) => _report.alreadyReported(claim: claim, touristId: touristId);

  Future<void> insertClaim({
    required ReportClaim claim,
    required String touristId,
  }) => _report.insertClaim(claim: claim, touristId: touristId);

  Future<int> countIdentical(ReportClaim claim) =>
      _report.countIdentical(claim);

  Future<int> countIssue(ReportClaim claim) => _report.countIssue(claim);

  Future<List<TouristLocation>> locationsForIssue(ReportClaim claim) =>
      _report.locationsForIssue(claim);

  Future<List<ClosureClaim>> closureClaimsForIssue(ReportClaim claim) =>
      _report.closureClaimsForIssue(claim);

  Future<void> deleteIdentical(ReportClaim claim) =>
      _report.deleteIdentical(claim);

  Future<void> deleteIssue(ReportClaim claim) => _report.deleteIssue(claim);

  Future<void> replaceOpeningHourDay({
    required ReportPlaceKind placeKind,
    required int placeId,
    required Weekday day,
    required List<OpeningHour> rows,
  }) {
    if (placeKind == ReportPlaceKind.restaurant) {
      return _restaurant.replaceOpeningHourDay(placeId, day, rows);
    }
    return _landmark.replaceOpeningHourDay(placeId, day, rows);
  }

  Future<void> updateItemPrice({
    required ReportItemKind itemKind,
    required int itemId,
    required double price,
  }) {
    if (itemKind == ReportItemKind.restaurantItem) {
      return _restaurant.updateItemPrice(itemId, price);
    }
    return _landmark.updateItemPrice(itemId, price);
  }

  Future<void> softRemoveItem({
    required ReportItemKind itemKind,
    required int itemId,
  }) {
    if (itemKind == ReportItemKind.restaurantItem) {
      return _restaurant.softRemoveItem(itemId);
    }
    return _landmark.softRemoveItem(itemId);
  }

  Future<int> countVisibleItems({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) {
    if (placeKind == ReportPlaceKind.restaurant) {
      return _restaurant.countVisibleItems(placeId);
    }
    return _landmark.countVisibleItems(placeId);
  }

  Future<void> removePlace({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) {
    if (placeKind == ReportPlaceKind.restaurant) {
      return _restaurant.removePlace(placeId);
    }
    return _landmark.removePlace(placeId);
  }

  Future<void> updateAddress({
    required ReportPlaceKind placeKind,
    required int placeId,
    required String address,
    required double latitude,
    required double longitude,
  }) {
    if (placeKind == ReportPlaceKind.restaurant) {
      return _restaurant.updateAddress(
        placeId,
        address,
        latitude: latitude,
        longitude: longitude,
      );
    }
    return _landmark.updateAddress(
      placeId,
      address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> freezePlace({
    required ReportPlaceKind placeKind,
    required int placeId,
    DateTime? closedUntil,
  }) {
    if (placeKind == ReportPlaceKind.restaurant) {
      return _restaurant.freezePlace(placeId, closedUntil: closedUntil);
    }
    return _landmark.freezePlace(placeId, closedUntil: closedUntil);
  }

  void clearMapCache() => _map.clearCache();
}
