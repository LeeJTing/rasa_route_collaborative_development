import 'package:meta/meta.dart' show protected;

import '../../domain_model/address_suggestion.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';
import '../../domain_model/report_outcome.dart';
import '../../domain_model/restaurant_item.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../domain_model/tourist_location.dart';
import '../repositories/auth_repository.dart';
import '../repositories/geocoding_repository.dart';
import '../repositories/map_repository.dart';
import '../repositories/report_repository.dart';
import '../repositories/restaurant_repository.dart';
import '../repositories/submitted_landmark_repository.dart';
import 'landmark_submission_logic.dart';
import 'report_moderation_rules.dart';

/// The report flow shared by catalogue restaurants AND submitted landmarks:
/// records one tourist's claim(s) about a place and, when enough DISTINCT
/// tourists make the IDENTICAL claim, auto-applies the fix.
///
/// This logic spans BOTH place kinds (the same categories, thresholds and
/// auto-apply actions exist for restaurants and landmarks), so it holds the
/// submitted-landmark repo AND the catalogue restaurant repo alongside the
/// shared `report` repo, `auth` and `map` (documented cross-place exception,
/// like `MapExplorationLogic`).
///
/// Flow per claim (see `ReportModerationRules` for the pure decisions):
///   1. resolve the signed-in tourist (reporting is signed-in-only);
///   2. dedupe - one tourist may claim a specific issue only once;
///   3. insert the claim row;
///   4. count identical claims (same issue + same canonical payload) from
///      distinct tourists; at/over the threshold, apply the fix and clear the
///      matched rows so the count starts fresh.
class ReportModerationLogic {
  ReportModerationLogic();

  // Test seam: each repository is behind a `@protected create*()` factory so a
  // subclass can inject a fake (the same DI convention ViewModels use), rather
  // than constructing real network-backed repositories.
  @protected
  ReportRepository createReportRepository() => ReportRepository();

  @protected
  RestaurantRepository createRestaurantRepository() => RestaurantRepository();

  @protected
  SubmittedLandmarkRepository createLandmarkRepository() =>
      SubmittedLandmarkRepository();

  @protected
  AuthRepository createAuthRepository() => AuthRepository();

  @protected
  MapRepository createMapRepository() => MapRepository();

  /// The address field's geocoder - the SAME OpenStreetMap/Nominatim
  /// repository the Add-Landmark form searches through, so a corrected
  /// address is composed and worded identically on both screens.
  @protected
  GeocodingRepository createGeocodingRepository() => GeocodingRepository();

  late final ReportRepository report = createReportRepository();
  late final RestaurantRepository restaurant = createRestaurantRepository();
  late final SubmittedLandmarkRepository landmark = createLandmarkRepository();
  late final AuthRepository auth = createAuthRepository();
  late final MapRepository map = createMapRepository();
  late final GeocodingRepository geocoding = createGeocodingRepository();

  /// Live address suggestions for the report page's address field -
  /// measured from [around] and sorted nearest first, exactly like the
  /// Add-Landmark form (the measuring/ordering rules are shared statics on
  /// `LandmarkSubmissionLogic`). `null` = the lookup failed; `[]` = nothing
  /// matched.
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => LandmarkSubmissionLogic.searchAddressesWith(
    geocoding,
    query: query,
    around: around,
  );

  /// The composed OSM address of one point - what the address field fills in
  /// when the report page's pin moves. Never throws.
  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      geocoding.reverseGeocodeAddress(location);

  /// How a suggestion's distance is labelled ("350 m", "1.2 km") - the same
  /// rule the Add-Landmark form uses.
  String formatDistance(double metres) =>
      LandmarkSubmissionLogic.formatDistanceLabel(metres);

  /// The place's current (non-removed) menu items for the report picker.
  Future<List<ReportableMenuItem>> reportableItemsFor({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) async {
    if (placeKind == ReportPlaceKind.restaurant) {
      final List<RestaurantItem> items = await restaurant.getReportableItems(
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
    final List<LandmarkItem> items = await landmark.getReportableItems(placeId);
    return <ReportableMenuItem>[
      for (final LandmarkItem item in items)
        ReportableMenuItem(
          itemKind: ReportItemKind.landmarkItem,
          id: item.id,
          // The variant the tourist captured, else the dictionary dish - a
          // report names the dish as the place lists it (see
          // `LandmarkItem.displayName`).
          name: item.displayName,
          price: item.price,
          isRemoved: item.isRemoved,
        ),
    ];
  }

  /// Submits [claims] against the place. Returns an aggregate [ReportSubmitOutcome].
  ///
  /// All claims must target the same place (they are built from one report
  /// page visit). [touristId] may be passed in by the caller (already
  /// resolved) or left null to resolve here; a null/empty resolved id means
  /// nothing is written and [ReportSubmitOutcome.requiresSignIn] is true.
  Future<ReportSubmitOutcome> submitClaims({
    required List<ReportClaim> claims,
    String? touristId,
  }) async {
    if (claims.isEmpty) {
      return const ReportSubmitOutcome();
    }
    final String? resolvedTouristId =
        touristId ?? await auth.currentTouristId();
    if (resolvedTouristId == null || resolvedTouristId.isEmpty) {
      return const ReportSubmitOutcome(requiresSignIn: true);
    }

    int submittedCount = 0;
    int duplicateCount = 0;
    final List<String> applied = <String>[];
    bool placeHiddenNow = false;
    bool wroteAnything = false;

    for (final ReportClaim claim in claims) {
      final bool duplicate = await report.alreadyReported(
        claim: claim,
        touristId: resolvedTouristId,
      );
      if (duplicate) {
        duplicateCount++;
        continue;
      }
      await report.insertClaim(claim: claim, touristId: resolvedTouristId);
      wroteAnything = true;
      submittedCount++;

      // Temporary closure is counted across DIFFERENT durations: ten tourists
      // saying "closed temporarily" (each possibly with its own duration) is
      // enough - at apply time the claims are resolved into the END DATE they
      // agree on (see `_applyClosedTemporarily`). Every other category needs
      // identical payloads (same hours / price / address / item).
      final bool temporaryClosure =
          claim.category == ReportCategory.closedTemporarily;
      final int count = temporaryClosure
          ? await report.countIssue(claim)
          : await report.countIdentical(claim);
      if (!ReportModerationRules.reachesThreshold(claim.category, count)) {
        continue;
      }

      final _ApplyResult result;
      if (temporaryClosure) {
        result = await _applyClosedTemporarily(claim);
        // Every claim contributed to crossing the threshold - clear the
        // whole issue so the next report starts a fresh count.
        await report.deleteIssue(claim);
      } else {
        result = await _applyFix(claim);
        // The fix matched this claim's identical group - clear those rows so
        // the next report starts a fresh count (per approved plan). A fix
        // that was HELD BACK (the pins do not agree on the spot yet) keeps
        // its rows, so each further valid report re-runs the consensus check.
        if (!result.heldBack) {
          await report.deleteIdentical(claim);
        }
      }
      if (result.label != null) applied.add(result.label!);
      if (result.hidPlace) placeHiddenNow = true;
    }

    if (wroteAnything && placeHiddenNow) {
      // Frozen/removed places are no longer 'available', so cached map pins
      // must go - the next read (after the UI leaves the page) has no pin.
      map.clearCache();
    }

    return ReportSubmitOutcome(
      requiresSignIn: false,
      alreadyReported: wroteAnything ? false : duplicateCount > 0,
      submittedCount: submittedCount,
      duplicateCount: duplicateCount,
      placeHiddenNow: placeHiddenNow,
      applied: List<String>.unmodifiable(applied),
    );
  }

  /// Applies the fix for one claim that reached its threshold. Temporary
  /// closure never reaches here - `submitClaims` handles it separately (it
  /// counts by issue and needs the whole issue's payloads to resolve the
  /// most-common duration).
  Future<_ApplyResult> _applyFix(ReportClaim claim) async {
    switch (claim.category) {
      case ReportCategory.operatingHours:
        return _applyHours(claim);
      case ReportCategory.itemPrice:
        return _applyItemPrice(claim);
      case ReportCategory.itemNotExist:
        return _applyItemNotExist(claim);
      case ReportCategory.address:
        return _applyAddress(claim);
      case ReportCategory.closedPermanently:
        return _applyClosedPermanently(claim);
      case ReportCategory.closedTemporarily:
        // Handled in `submitClaims` (issue-counted); never dispatched here.
        return const _ApplyResult();
    }
  }

  Future<_ApplyResult> _applyHours(ReportClaim claim) async {
    final Weekday? day = claim.day;
    if (day == null) return const _ApplyResult();
    final List<ProposedDayHours> proposed =
        ReportModerationRules.parseHoursPayload(claim.payload);
    if (proposed.isEmpty) return const _ApplyResult();
    final List<OpeningHour> rows = <OpeningHour>[
      for (final ProposedDayHours p in proposed)
        OpeningHour(
          id: 0,
          day: day,
          status: p.status,
          opensAt: p.status == DayStatus.open ? p.opensAt : null,
          closesAt: p.status == DayStatus.open ? p.closesAt : null,
        ),
    ];
    if (claim.placeKind == ReportPlaceKind.restaurant) {
      await restaurant.replaceRestaurantOpeningHourDay(
        claim.placeId,
        day,
        rows,
      );
    } else {
      await landmark.replaceLandmarkOpeningHourDay(claim.placeId, day, rows);
    }
    return _ApplyResult(label: '${_dayLabel(day)} hours updated');
  }

  Future<_ApplyResult> _applyItemPrice(ReportClaim claim) async {
    final int? itemId = claim.itemId;
    if (itemId == null) return const _ApplyResult();
    final double? price = double.tryParse(
      claim.payload.replaceFirst('price:', ''),
    );
    if (price == null) return const _ApplyResult();
    if (claim.itemKind == ReportItemKind.restaurantItem) {
      await restaurant.updateRestaurantItemPrice(itemId, price);
    } else if (claim.itemKind == ReportItemKind.landmarkItem) {
      await landmark.updateLandmarkItemPrice(itemId, price);
    } else {
      return const _ApplyResult();
    }
    return const _ApplyResult(label: 'Price updated');
  }

  Future<_ApplyResult> _applyItemNotExist(ReportClaim claim) async {
    final int? itemId = claim.itemId;
    if (itemId == null) return const _ApplyResult();
    if (claim.itemKind == ReportItemKind.restaurantItem) {
      await restaurant.softRemoveRestaurantItem(itemId);
      // Price/not-exist claims about this item are moot now - clear them.
      await report.deleteIssue(claim);
      final int remaining = await restaurant.countVisibleRestaurantItems(
        claim.placeId,
      );
      if (remaining == 0) {
        await restaurant.removeRestaurant(claim.placeId);
        return const _ApplyResult(
          label: 'Item removed; restaurant hidden (no items left)',
          hidPlace: true,
        );
      }
      return const _ApplyResult(label: 'Item removed from menu');
    }
    if (claim.itemKind == ReportItemKind.landmarkItem) {
      await landmark.softRemoveLandmarkItem(itemId);
      await report.deleteIssue(claim);
      final int remaining = await landmark.countVisibleLandmarkItems(
        claim.placeId,
      );
      if (remaining == 0) {
        await landmark.removeLandmark(claim.placeId);
        return const _ApplyResult(
          label: 'Item removed; landmark hidden (no items left)',
          hidPlace: true,
        );
      }
      return const _ApplyResult(label: 'Item removed from menu');
    }
    return const _ApplyResult();
  }

  /// Applies the accepted address fix: the reported text AND the spot the
  /// VALID pins agree on.
  ///
  /// Two rules decide the location (user's design, 2026-09-13): only claims
  /// whose reporter was on site counted toward the threshold in the first
  /// place, and the coordinates move only when at least three of those pins
  /// fall within 30 m of their median - the median of THOSE pins is what gets
  /// written, so a dissenting tap cannot drag the place.
  ///
  /// Below three agreeing pins the fix is HELD BACK: nothing is written and
  /// the claims are KEPT (see [submitClaims]), so every further valid report
  /// re-runs this check until the tourists agree.
  Future<_ApplyResult> _applyAddress(ReportClaim claim) async {
    final String address = claim.payload.replaceFirst('address:', '').trim();
    if (address.isEmpty) return const _ApplyResult();
    final List<TouristLocation> pins = await report.locationsForIssue(claim);
    final TouristLocation? agreed = ReportModerationRules.consensusLocation(
      pins,
    );
    if (agreed == null) return const _ApplyResult(heldBack: true);
    final double latitude = agreed.latitude;
    final double longitude = agreed.longitude;
    if (claim.placeKind == ReportPlaceKind.restaurant) {
      await restaurant.updateRestaurantAddress(
        claim.placeId,
        address,
        latitude: latitude,
        longitude: longitude,
      );
    } else {
      await landmark.updateLandmarkAddress(
        claim.placeId,
        address,
        latitude: latitude,
        longitude: longitude,
      );
    }
    // A moved pin is new map data, so the map caches are dropped the same way
    // a freeze drops them.
    map.clearCache();
    return const _ApplyResult(label: 'Address updated');
  }

  Future<_ApplyResult> _applyClosedPermanently(ReportClaim claim) async {
    if (claim.placeKind == ReportPlaceKind.restaurant) {
      await restaurant.freezeRestaurant(claim.placeId);
    } else {
      await landmark.freezeLandmark(claim.placeId);
    }
    return const _ApplyResult(
      label: 'Place hidden (closed permanently)',
      hidPlace: true,
    );
  }

  Future<_ApplyResult> _applyClosedTemporarily(ReportClaim claim) async {
    // The claims may carry different durations - they are normalised to the
    // END DATE each voter meant (`created_at + duration`), so staggered
    // reports of the same closure vote together and the most-voted date wins
    // (ties -> the later date). The date is stored verbatim; one already in
    // the past just means the place reads as open again immediately.
    final List<ClosureClaim> issueClaims = await report.closureClaimsForIssue(
      claim,
    );
    final DateTime? closedUntil = ReportModerationRules.resolveClosureUntil(
      issueClaims,
    );
    if (claim.placeKind == ReportPlaceKind.restaurant) {
      await restaurant.freezeRestaurant(
        claim.placeId,
        closedUntil: closedUntil,
      );
    } else {
      await landmark.freezeLandmark(claim.placeId, closedUntil: closedUntil);
    }
    return const _ApplyResult(
      label: 'Place hidden (closed temporarily)',
      hidPlace: true,
    );
  }
}

/// Result of one auto-apply: an optional human label for the confirmation
/// message, and whether the action hid the whole place (freeze/remove).
class _ApplyResult {
  const _ApplyResult({
    this.label,
    this.hidPlace = false,
    this.heldBack = false,
  });

  /// The label added to `ReportSubmitOutcome.applied` (null = nothing
  /// applied).
  final String? label;

  /// True when the place is now hidden (frozen/removed) - the caller leaves
  /// the map and drops the pin.
  final bool hidPlace;

  /// True when the fix was DELIBERATELY not written yet: an address report's
  /// pins do not agree on a spot, so its claims are kept and the consensus
  /// check re-runs as more valid reports arrive.
  final bool heldBack;
}

String _dayLabel(Weekday day) => switch (day) {
  Weekday.monday => 'Monday',
  Weekday.tuesday => 'Tuesday',
  Weekday.wednesday => 'Wednesday',
  Weekday.thursday => 'Thursday',
  Weekday.friday => 'Friday',
  Weekday.saturday => 'Saturday',
  Weekday.sunday => 'Sunday',
};
