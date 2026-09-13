import '../../domain_model/malaysia_boundary.dart';
import '../../domain_model/region.dart';

/// Geographic rules for the Add Landmark location (UC500, A9).
///
/// Pure geometry - no Flutter, no network, no clients - so both the logic
/// layer and its tests can reason about a coordinate without a device.
///
/// Both predicates are point-in-polygon tests (ray casting), answered in two
/// steps so the form can never disagree with the map:
///   1. [MalaysiaBoundary.publishedRings] - the rings the MAP fetched for
///      itself (the real coastline, buffered ~2 km, plus the islands no
///      boundary dataset has). The map publishes them once per process, so a
///      dot the map draws inside Malaysia is a location the form accepts.
///   2. The built-in polygons below, used until then (cold start with no
///      connection, unit tests): Peninsular Malaysia, East Malaysia, and the
///      island rings the map had to add for exactly this reason - Langkawi,
///      Tioman, Redang and Perhentian, the Semporna islands, Payar - copied
///      from `MalaysiaOutlineDataModel` (`maskCatalogue` /
///      `outlyingIslands`).
///
/// NOTE: these are deliberately simplified validation boundaries, not
/// survey-grade borders. They exist to reject obvious out-of-country /
/// at-sea coordinates (A9), not to arbitrate a contested border - and a
/// tourist whose dot the map draws inside Malaysia must never be turned away
/// (user report 2026-09-14: mocked fixes on Pulau Redang and in Perlis were
/// rejected because the hand-drawn polygon had no island and clipped Perlis's
/// west coast).
class LocationRules {
  const LocationRules._();

  /// Simplified Peninsular Malaysia land polygon as (latitude, longitude)
  /// points, traced clockwise from the north-west along the coastline.
  static const List<List<(double, double)>> _peninsular =
      <List<(double, double)>>[
        <(double, double)>[
          // Perlis's west coast runs at ~100.11-100.15: the old edge at
          // 100.22 put Kangar (6.44, 100.20) and Kuala Perlis (6.40, 100.13)
          // in the sea (user report 2026-09-14).
          (6.72, 100.11),
          (6.42, 100.11),
          (6.10, 100.15),
          (5.90, 100.20),
          (5.60, 100.20),
          (5.25, 100.25),
          (4.90, 100.35),
          (4.55, 100.50),
          (4.20, 100.58),
          (3.90, 100.70),
          (3.60, 100.78),
          (3.25, 100.95),
          (2.90, 101.02),
          (2.55, 101.15),
          (2.30, 101.50),
          (2.05, 102.05),
          (1.85, 102.60),
          (1.60, 103.00),
          (1.40, 103.30),
          (1.30, 103.50),
          (1.45, 103.85),
          (1.65, 104.10),
          (2.00, 104.20),
          (2.45, 104.10),
          (2.90, 103.80),
          (3.30, 103.50),
          (3.80, 103.40),
          (4.20, 103.45),
          (4.60, 103.55),
          (4.80, 103.42),
          (5.00, 103.20),
          (5.20, 103.20),
          (5.35, 103.16),
          (5.55, 103.05),
          (5.83, 102.60),
          (6.15, 102.50),
          (6.50, 102.20),
          (6.72, 102.15),
        ],
      ];

  /// Simplified East Malaysia (Sarawak + Sabah) land polygon as
  /// (latitude, longitude) points.
  static const List<List<(double, double)>> _eastMalaysia =
      <List<(double, double)>>[
        <(double, double)>[
          (1.55, 110.35),
          (1.70, 110.70),
          (1.95, 111.10),
          (2.20, 111.55),
          (2.40, 111.90),
          (2.70, 112.30),
          (3.05, 112.70),
          (3.45, 113.10),
          (3.90, 113.55),
          (4.30, 113.90),
          (4.60, 114.10),
          (4.90, 114.30),
          (5.05, 114.60),
          (5.25, 114.95),
          (5.55, 115.30),
          (5.90, 115.80),
          (6.10, 116.30),
          (6.30, 116.55),
          (6.70, 116.90),
          (7.00, 117.00),
          (6.95, 117.30),
          (6.60, 117.70),
          (6.20, 118.00),
          (5.84, 118.12),
          (5.40, 118.20),
          (5.05, 118.60),
          (4.70, 118.40),
          (4.24, 118.05),
          (3.95, 117.30),
          (3.55, 116.80),
          (3.15, 116.30),
          (2.85, 115.75),
          (2.55, 115.00),
          (2.25, 114.35),
          (2.00, 113.70),
          (1.80, 113.00),
          (1.60, 112.20),
        ],
      ];

  /// The island rings the coastline tracing misses - copied from the map's
  /// own data (`MalaysiaOutlineDataModel.maskCatalogue` + `outlyingIslands`),
  /// because a tourist standing on one of them is plainly in Malaysia: without
  /// these a mocked Pulau Redang fix was rejected (user report 2026-09-14).
  /// Keep them in step with the map's rings.
  static const List<List<(double, double)>> _islands = <List<(double, double)>>[
    // Langkawi.
    <(double, double)>[
      (6.520, 99.580),
      (6.520, 99.980),
      (6.130, 99.980),
      (6.130, 99.580),
    ],
    // Tioman.
    <(double, double)>[
      (2.950, 104.020),
      (2.950, 104.300),
      (2.620, 104.300),
      (2.620, 104.020),
    ],
    // Redang and Perhentian.
    <(double, double)>[
      (6.000, 102.620),
      (6.000, 103.120),
      (5.680, 103.120),
      (5.680, 102.620),
    ],
    // Sipadan, Mabul and Ligitan, off Semporna.
    <(double, double)>[
      (4.350, 118.500),
      (4.350, 118.750),
      (4.050, 118.750),
      (4.050, 118.500),
    ],
    // Pulau Payar, the marine park south of Langkawi.
    <(double, double)>[
      (6.150, 99.850),
      (6.150, 100.020),
      (5.980, 100.020),
      (5.980, 99.850),
    ],
  ];

  static const List<List<(double, double)>> _allPolygons =
      <List<(double, double)>>[..._peninsular, ..._eastMalaysia, ..._islands];

  /// True when (lat, lon) is inside Malaysia's land boundary.
  ///
  /// The map's own rings win while they are published (see
  /// [MalaysiaBoundary]): they are the real coastline, and the Add-Landmark
  /// form must give the same answer the map draws.
  static bool isWithinMalaysia(double lat, double lon) {
    final List<CountryOutline>? published = MalaysiaBoundary.publishedRings;
    if (published != null) {
      for (final CountryOutline outline in published) {
        if (_pointInOutline(lat, lon, outline.ring)) return true;
      }
      return false;
    }
    for (final List<(double, double)> polygon in _allPolygons) {
      if (_pointInPolygon(lat, lon, polygon)) return true;
    }
    return false;
  }

  /// True when (lat, lon) is on Malaysian land.
  ///
  /// With the coastline-following boundary this currently agrees with
  /// [isWithinMalaysia] - a point inside Malaysia's boundary IS on Malaysian
  /// land. It is kept as a separate predicate because it encodes a distinct
  /// product rule ("must be on land"), and if a future policy adds a sea mask
  /// (e.g. "in Malaysian waters but not on land", sourced from OSM/Overpass),
  /// only this method needs to change - call sites stay untouched.
  static bool isOnLand(double lat, double lon) => isWithinMalaysia(lat, lon);

  /// Ray-casting point-in-polygon test. Lat is treated as y, lon as x.
  ///
  /// Shared by both datasets - the built-in `(lat, lon)` tuples and the
  /// published [GeoPoint] rings - so the two can never differ in HOW a point
  /// is judged, only in WHICH boundary they judge it against.
  static bool _pointInRing<T>(
    double lat,
    double lon,
    List<T> ring,
    double Function(T point) latOf,
    double Function(T point) lonOf,
  ) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final double latI = latOf(ring[i]);
      final double lonI = lonOf(ring[i]);
      final double latJ = latOf(ring[j]);
      final double lonJ = lonOf(ring[j]);
      final bool crosses =
          ((latI > lat) != (latJ > lat)) &&
          (lon < (lonJ - lonI) * (lat - latI) / (latJ - latI) + lonI);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  static bool _pointInPolygon(
    double lat,
    double lon,
    List<(double, double)> polygon,
  ) => _pointInRing<(double, double)>(
    lat,
    lon,
    polygon,
    ((double, double) point) => point.$1,
    ((double, double) point) => point.$2,
  );

  static bool _pointInOutline(double lat, double lon, List<GeoPoint> ring) =>
      _pointInRing<GeoPoint>(
        lat,
        lon,
        ring,
        (GeoPoint point) => point.latitude,
        (GeoPoint point) => point.longitude,
      );
}
