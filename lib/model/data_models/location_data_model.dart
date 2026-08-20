import '../../core/json_model.dart';

/// A device GPS fix.
///
/// Not a database table - this is what `DeviceCapabilityManager` produces and
/// `LocationMonitor` publishes. It is a data model (not a domain model) because
/// it is also cached to local storage as JSON.
class LocationDataModel implements JsonModel {
  const LocationDataModel({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.capturedAt,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy reported by the platform, in metres.
  final double? accuracyMeters;

  /// When the fix was taken. Used to decide whether a cached fix is stale.
  final DateTime? capturedAt;

  /// Sentinel used before the first fix arrives.
  static const LocationDataModel unknown = LocationDataModel(
    latitude: 0,
    longitude: 0,
  );

  bool get isKnown => latitude != 0 || longitude != 0;

  factory LocationDataModel.fromJson(Map<String, dynamic> json) {
    return LocationDataModel(
      latitude: JsonReader.asDouble(json['latitude']),
      longitude: JsonReader.asDouble(json['longitude']),
      accuracyMeters: JsonReader.asDoubleOrNull(json['accuracy_meters']),
      capturedAt: JsonReader.asDateOrNull(json['captured_at']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_meters': accuracyMeters,
    'captured_at': capturedAt?.toIso8601String(),
  };

  @override
  String toString() =>
      'LocationDataModel($latitude, $longitude, +/-${accuracyMeters}m)';
}
