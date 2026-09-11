/// One row from `map_food_clusters` or `map_food_pins`.
///
/// Both functions return the same shape on purpose, so there is one decoder and
/// one code path whether the map is showing aggregates or individual places:
///
///   source        'cluster' | 'restaurant' | 'submittedLandmark'
///   reference_id  the row's id - null for a cluster
///   point_count   1 for a real place, N for a cluster
///
/// A data model mirrors what the backend sends and owns `fromJson`. Turning it
/// into something the app reasons about is `MapRepository`'s job.
class MapMarkerDataModel {
  const MapMarkerDataModel({
    required this.source,
    required this.referenceId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    required this.pointCount,
  });

  factory MapMarkerDataModel.fromJson(Map<String, dynamic> json) =>
      MapMarkerDataModel(
        source: _asString(json['source']),
        referenceId: _asIntOrNull(json['reference_id']),
        name: _asString(json['name']),
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        rating: _asDoubleOrNull(json['rating']),
        imageUrl: _asStringOrNull(json['image_url']),
        pointCount: _asIntOrNull(json['point_count']) ?? 1,
      );

  final String source;
  final int? referenceId;
  final String name;
  final double latitude;
  final double longitude;
  final double? rating;
  final String? imageUrl;
  final int pointCount;

  /// A cluster row carries no id and stands for more than itself.
  bool get isCluster => source == 'cluster';

  // PostgREST hands numerics back as String on some drivers, so every read goes
  // through one of these rather than a raw cast.

  static String _asString(Object? value) => value == null ? '' : '$value';

  static String? _asStringOrNull(Object? value) {
    final String text = _asString(value).trim();
    return text.isEmpty ? null : text;
  }

  static double _asDouble(Object? value) => _asDoubleOrNull(value) ?? 0;

  static double? _asDoubleOrNull(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static int? _asIntOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }
}
