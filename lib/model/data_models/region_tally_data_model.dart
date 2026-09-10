/// One row from `map_region_distribution` - one Malaysian state or federal
/// territory, with its counts already worked out by Postgres.
///
/// **Why this row exists.** The heatmap used to be built by downloading every
/// restaurant in Malaysia (12,660 rows) and every menu entry (78,355) and
/// running a point-in-polygon test per place in Dart, on every redraw. The
/// counting now happens in Postgres against real administrative boundaries and
/// this is what comes back: sixteen rows.
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
    required this.placeCount,
    required this.foodCount,
    required this.restaurantCount,
    required this.landmarkCount,
  });

  /// The function also returns the area's centre and bounding box. They are not
  /// decoded: the outlines the heatmap paints come from
  /// `MalaysiaRegionDataModel`, which carries its own centres.
  factory RegionTallyDataModel.fromJson(Map<String, dynamic> json) =>
      RegionTallyDataModel(
        code: _asString(json['code']),
        name: _asString(json['name']),
        placeCount: _asInt(json['place_count']),
        foodCount: _asInt(json['food_count']),
        restaurantCount: _asInt(json['restaurant_count']),
        landmarkCount: _asInt(json['landmark_count']),
      );

  final String code;
  final String name;
  final int placeCount;
  final int foodCount;
  final int restaurantCount;
  final int landmarkCount;

  // PostgREST hands numerics back as String on some drivers, so every read goes
  // through one of these rather than a raw cast.

  static String _asString(Object? value) => value == null ? '' : '$value';

  static int _asInt(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
