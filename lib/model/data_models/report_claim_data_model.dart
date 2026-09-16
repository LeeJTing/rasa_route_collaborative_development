import '../../core/json_model.dart';

/// Wire shape of `public.report` - ONE claim row.
///
/// The app reasons about claims through the domain `ReportClaim` (the issue:
/// kind, place, reason, item/day and the canonical payload) - and this data
/// model is the ROW that carries it: the wire id (`report_id`, identity) and
/// the filing timestamp (`created_at`, the one-year expiry clock behind
/// `isReportClaimExpired`) that the domain type deliberately does not hold.
/// `ReportRepository` converts every read through [fromJson] and builds every
/// insert through [toJson], so the column names live in exactly one place -
/// the same data-model ↔ domain-model conversion every other table's
/// repository does.
class ReportClaimDataModel implements JsonModel {
  const ReportClaimDataModel({
    this.reportId,
    required this.kind,
    required this.placeId,
    required this.reason,
    this.itemKind,
    this.itemId,
    this.day,
    this.payload,
    this.latitude,
    this.longitude,
    this.locationValid = false,
    this.touristId,
    this.createdAt,
  });

  /// `report.report_id` (bigint identity, PK). Null on a row being INSERTED -
  /// the DB assigns it.
  final int? reportId;

  /// `report.kind` - 'landmark' | 'restaurant' (see `ReportPlaceKind`).
  final String kind;

  /// `report.place_id` - the place the claim is about.
  final int placeId;

  /// `report.reason` - the category NAME (`ReportCategory.name`).
  final String reason;

  /// `report.item_kind` - 'landmark_item' | 'restaurant_item' for the
  /// item-price / item-not-exist claims, null for every other category.
  final String? itemKind;

  /// `report.item_id` - the disputed menu row, when the claim is about one.
  final int? itemId;

  /// `report.day` - the weekday NAME for an operating-hours claim.
  final String? day;

  /// `report.payload` - the CANONICAL proposed value (see `ReportClaim
  /// .payload`); identical claims are grouped by exact payload equality.
  /// Null for the `closedPermanently` category, which carries no value.
  final String? payload;

  /// `report.latitude` / `longitude` - the pin an ADDRESS claim carried
  /// (null for every other category): the exact spot, which is what the fix
  /// applies along with the text.
  final double? latitude;
  final double? longitude;

  /// `report.location_valid` - the silent on-site check's verdict. Only
  /// valid claims count toward a threshold (and only they may steer an
  /// applied pin/end date).
  final bool locationValid;

  /// `report.tourist_id` - the reporter (uuid), null on an anonymous row.
  final String? touristId;

  /// `report.created_at` - when the claim was filed; a claim past
  /// `reportClaimLifetime` stops counting and stops blocking its tourist
  /// (`isReportClaimExpired`).
  final DateTime? createdAt;

  factory ReportClaimDataModel.fromJson(Map<String, dynamic> json) {
    return ReportClaimDataModel(
      reportId: JsonReader.asIntOrNull(json['report_id']),
      kind: JsonReader.asString(json['kind']),
      placeId: JsonReader.asInt(json['place_id']),
      reason: JsonReader.asString(json['reason']),
      itemKind: JsonReader.asStringOrNull(json['item_kind']),
      itemId: JsonReader.asIntOrNull(json['item_id']),
      day: JsonReader.asStringOrNull(json['day']),
      payload: JsonReader.asStringOrNull(json['payload']),
      latitude: JsonReader.asDoubleOrNull(json['latitude']),
      longitude: JsonReader.asDoubleOrNull(json['longitude']),
      locationValid: JsonReader.asBool(json['location_valid']),
      touristId: JsonReader.asStringOrNull(json['tourist_id']),
      createdAt: JsonReader.asDateOrNull(json['created_at']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'report_id': reportId,
    'kind': kind,
    'place_id': placeId,
    'reason': reason,
    'item_kind': itemKind,
    'item_id': itemId,
    'day': day,
    'payload': payload,
    'latitude': latitude,
    'longitude': longitude,
    'location_valid': locationValid,
    'tourist_id': touristId,
    'created_at': createdAt?.toIso8601String(),
  };
}
