/// One row from `map_region_distribution` - a single area of whichever level
/// of the heatmap is being viewed, with its counts already worked out by
/// Postgres.
///
/// **Why this row exists.** The heatmap used to be built by downloading every
/// restaurant in Malaysia (12,660 rows) and every menu entry (78,355) and
/// running a point-in-polygon test per place in Dart, on every redraw. The
/// counting now happens in Postgres against real administrative boundaries and
/// this is what comes back: sixteen rows for the country, nine for Selangor's
/// districts.
///
/// `place_count` and `food_count` answer the *current* filter; `restaurant_count`
/// and `landmark_count` are the unfiltered totals, maintained by trigger on
/// `region_boundary`.
///
/// A data model mirrors what the backend sends and owns `fromJson`. Turning it
/// into a [Region] and a [RegionAvailability] is `MapRepository`'s job.
class RegionTallyDataModel {
  const RegionTallyDataModel({
    required this.code,
    required this.name,
    required this.parentCode,
    required this.centreLatitude,
    required this.centreLongitude,
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
    required this.placeCount,
    required this.foodCount,
    required this.restaurantCount,
    required this.landmarkCount,
  });

  factory RegionTallyDataModel.fromJson(Map<String, dynamic> json) =>
      RegionTallyDataModel(
        code: _asString(json['code']),
        name: _asString(json['name']),
        parentCode: _asStringOrNull(json['parent_code']),
        centreLatitude: _asDouble(json['centre_latitude']),
        centreLongitude: _asDouble(json['centre_longitude']),
        minLatitude: _asDouble(json['min_latitude']),
        minLongitude: _asDouble(json['min_longitude']),
        maxLatitude: _asDouble(json['max_latitude']),
        maxLongitude: _asDouble(json['max_longitude']),
        placeCount: _asInt(json['place_count']),
        foodCount: _asInt(json['food_count']),
        restaurantCount: _asInt(json['restaurant_count']),
        landmarkCount: _asInt(json['landmark_count']),
      );

  final String code;
  final String name;
  final String? parentCode;
  final double centreLatitude;
  final double centreLongitude;
  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;
  final int placeCount;
  final int foodCount;
  final int restaurantCount;
  final int landmarkCount;

  // PostgREST hands numerics back as String on some drivers, so every read goes
  // through one of these rather than a raw cast.

  static String _asString(Object? value) => value == null ? '' : '$value';

  static String? _asStringOrNull(Object? value) {
    final String text = _asString(value).trim();
    return text.isEmpty ? null : text;
  }

  static double _asDouble(Object? value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static int _asInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}

/// One row from `map_region_rings` - the outline an area is painted with.
///
/// `ring` is the `coordinates` member of a GeoJSON MultiPolygon: a list of
/// polygons, each a list of linear rings, each a list of `[longitude, latitude]`
/// pairs. Only the outer ring of each polygon is kept - the heatmap paints
/// filled areas, and a lake drawn as a hole would show the map background
/// through the fill.
class RegionRingDataModel {
  const RegionRingDataModel({
    required this.code,
    required this.name,
    required this.parentCode,
    required this.parts,
  });

  factory RegionRingDataModel.fromJson(Map<String, dynamic> json) =>
      RegionRingDataModel(
        code: RegionTallyDataModel._asString(json['code']),
        name: RegionTallyDataModel._asString(json['name']),
        parentCode: RegionTallyDataModel._asStringOrNull(json['parent_code']),
        parts: _asParts(json['ring']),
      );

  final String code;
  final String name;
  final String? parentCode;

  /// One entry per polygon, each a list of `[longitude, latitude]` pairs.
  final List<List<List<double>>> parts;

  static List<List<List<double>>> _asParts(Object? value) {
    if (value is! List) return const <List<List<double>>>[];
    final List<List<List<double>>> parts = <List<List<double>>>[];
    for (final Object? polygon in value) {
      if (polygon is! List || polygon.isEmpty) continue;
      final Object? outer = polygon.first;
      if (outer is! List) continue;
      final List<List<double>> points = <List<double>>[];
      for (final Object? pair in outer) {
        if (pair is! List || pair.length < 2) continue;
        final double longitude = RegionTallyDataModel._asDouble(pair[0]);
        final double latitude = RegionTallyDataModel._asDouble(pair[1]);
        points.add(<double>[longitude, latitude]);
      }
      if (points.length >= 3) parts.add(points);
    }
    return parts;
  }
}
