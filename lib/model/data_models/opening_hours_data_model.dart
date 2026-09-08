import '../../core/json_model.dart';

/// Wire shape of `public.opening_hours`.
///
/// Exactly one of [landmarkId] / [restaurantId] is populated per row.
/// `opening_time` / `closing_time` are Postgres `time` values and arrive as
/// `"HH:MM:SS"` strings - kept as strings here, parsed by repositories.
class OpeningHoursDataModel implements JsonModel {
  const OpeningHoursDataModel({
    required this.openingHoursId,
    required this.day,
    required this.status,
    this.openingTime,
    this.closingTime,
    this.landmarkId,
    this.restaurantId,
  });

  /// `opening_hours.opening_hours_id` (bigint, PK - no identity, supply it).
  final int openingHoursId;

  /// `Monday` ... `Sunday`.
  final String day;

  /// `open`, `closed`, or `unknown`.
  final String status;

  /// `"HH:MM:SS"` or null when the venue is closed / hours unknown.
  final String? openingTime;

  /// `"HH:MM:SS"` or null.
  final String? closingTime;

  final int? landmarkId;
  final int? restaurantId;

  factory OpeningHoursDataModel.fromJson(Map<String, dynamic> json) {
    return OpeningHoursDataModel(
      openingHoursId: JsonReader.asInt(json['opening_hours_id']),
      day: JsonReader.asString(json['day']),
      status: JsonReader.asString(json['status']),
      openingTime: JsonReader.asStringOrNull(json['opening_time']),
      closingTime: JsonReader.asStringOrNull(json['closing_time']),
      landmarkId: JsonReader.asIntOrNull(json['landmark_id']),
      restaurantId: JsonReader.asIntOrNull(json['restaurant_id']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'opening_hours_id': openingHoursId,
    'day': day,
    'status': status,
    'opening_time': openingTime,
    'closing_time': closingTime,
    'landmark_id': landmarkId,
    'restaurant_id': restaurantId,
  };
}
