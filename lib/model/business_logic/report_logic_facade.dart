import '../../domain_model/address_suggestion.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';
import '../../domain_model/report_outcome.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/tourist_location.dart';
import 'landmark_submission_logic.dart';
import 'report_moderation_logic.dart';
import 'report_moderation_rules.dart';
import 'opening_hours_logic.dart';

/// The shared report flow (restaurant + submitted landmark): loading the
/// place's current menu items for the picker, submitting one tourist's claims,
/// and the threshold/auto-apply rules. Used by the full-screen report page
/// (`ReportPlaceViewModel`), which is reached from BOTH the restaurant detail
/// and the landmark place detail screens.
///
/// LOGIC FACADE - a ViewModel holds ONE of these and talks to it. No business
/// rules live here - `ReportModerationLogic` holds the flow, and the pure
/// `ReportModerationRules` holds thresholds/payloads - and it never imports
/// Flutter.
class ReportLogicFacade {
  ReportLogicFacade();

  final ReportModerationLogic moderation = ReportModerationLogic();

  // ===========================================================================
  // Report page data
  // ===========================================================================

  /// The place's current (non-removed) menu items for the item picker.
  Future<List<ReportableMenuItem>> reportableItemsFor({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) => moderation.reportableItemsFor(placeKind: placeKind, placeId: placeId);

  // ===========================================================================
  // Submitting claims
  // ===========================================================================

  /// Records the tourist's claims and auto-applies any that crossed their
  /// threshold. See `ReportModerationLogic.submitClaims`.
  Future<ReportSubmitOutcome> submitClaims({
    required List<ReportClaim> claims,
    String? touristId,
  }) => moderation.submitClaims(claims: claims, touristId: touristId);

  // ===========================================================================
  // Pure rules (thresholds etc.), re-exposed flat for the UI
  // ===========================================================================

  /// How many identical claims are needed before a fix is auto-applied.
  int thresholdFor(ReportCategory category) =>
      ReportModerationRules.thresholdFor(category);

  String? priceError(String value, {bool required = false}) =>
      ReportModerationRules.priceError(value, required: required);

  String? addressError(String value, {bool required = false}) =>
      ReportModerationRules.addressError(value, required: required);

  /// Live address suggestions for the report page's address field - the same
  /// OpenStreetMap lookup the Add-Landmark form uses, measured from [around]
  /// and sorted nearest first. `null` = the lookup failed; `[]` = nothing
  /// matched.
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) => moderation.searchAddresses(query: query, around: around);

  /// The composed address of a point ([location]) - what fills the address
  /// field when the report page's pin moves. Null when OpenStreetMap has
  /// nothing usable there. Never throws.
  Future<String?> reverseGeocodeAddress(TouristLocation location) =>
      moderation.reverseGeocodeAddress(location);

  /// How a suggestion's distance is labelled ("350 m", "1.2 km") - the same
  /// wording the Add-Landmark form uses.
  String formatDistance(double metres) => moderation.formatDistance(metres);

  /// Whether the reporter's own fix is close enough to the spot they are
  /// reporting about for the claim to count (see
  /// `ReportModerationRules.isWithinOnsiteRange`). The ViewModel feeds it the
  /// raw GPS fix; the rule - and the radius - stay in the logic layer.
  bool isWithinOnsiteRange(TouristLocation reporter, TouristLocation target) =>
      ReportModerationRules.isWithinOnsiteRange(reporter, target);

  /// The shortest typed query that triggers address suggestions - the same
  /// two characters the Add-Landmark form requires.
  int get minAddressSearchLength =>
      LandmarkSubmissionLogic.minAddressSearchLength;

  String? closureError(
    String value,
    ClosureUnit unit, {
    bool required = false,
  }) => ReportModerationRules.closureError(value, unit, required: required);

  String? operatingHoursError(Map<Weekday, List<OpeningHour>> operatingHours) =>
      ReportModerationRules.operatingHoursError(operatingHours);

  /// The encoded close for an edited hours row: a closing time at or before
  /// the opening time means the NEXT day - "10:00 -> 02:00" becomes
  /// 600 -> 1560 (minutes past midnight + 1440). See
  /// `OpeningHoursLogic.encodeClose` / `OpeningHoursRows`.
  int encodeCloseTime({required int opensAt, required int closeMinutes}) =>
      OpeningHoursLogic.encodeClose(
        opensAt: opensAt,
        closeMinutes: closeMinutes,
      );

  /// Canonical payload for one day's proposed hours (see
  /// `ReportModerationRules.hoursPayload`). Exposed so the report form and
  /// the claim-matching logic produce IDENTICAL strings - the page builds the
  /// claim payload through this facade, never a private mirror.
  String hoursPayload(List<ProposedDayHours> dayRows) =>
      ReportModerationRules.hoursPayload(dayRows);

  /// Canonical payload for a proposed price (see
  /// `ReportModerationRules.pricePayload`).
  String pricePayload(double price) =>
      ReportModerationRules.pricePayload(price);

  /// Canonical payload for a proposed address (see
  /// `ReportModerationRules.addressPayload`).
  String addressPayload(String address) =>
      ReportModerationRules.addressPayload(address);

  /// Canonical payload for a temporary closure (see
  /// `ReportModerationRules.temporaryClosurePayload`).
  String temporaryClosurePayload(ProposedClosure duration) =>
      ReportModerationRules.temporaryClosurePayload(duration);

  /// Canonical payload for an item-not-exist claim (a constant - the issue is
  /// the item, so there is no value to format).
  String get itemNotExistPayload => ReportModerationRules.itemNotExistPayload;

  /// Canonical payload for a permanent closure (a constant).
  String get closedPermanentlyPayload =>
      ReportModerationRules.closedPermanentlyPayload;
}
