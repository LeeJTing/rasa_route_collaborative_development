/// A Malaysian state or federal territory, as drawn on the REQ102 heatmap.
///
/// REQ102_1 - the map covers only Malaysia, so this is the complete set of
/// regions the dashboard will ever show. The catalogue itself lives in
/// `lib/model/data_models/malaysia_region_data_model.dart`; `MapRepository`
/// converts it into these.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class Region {
  const Region({
    required this.code,
    required this.name,
    required this.centreLatitude,
    required this.centreLongitude,
    required this.defaultZoom,
    required this.boundary,
    required this.places,
    this.level = stateLevel,
    this.parentCode,
    this.rings = const <List<GeoPoint>>[],
    this.minLatitude,
    this.minLongitude,
    this.maxLatitude,
    this.maxLongitude,
  });

  /// A state or federal territory - the level the heatmap opens on.
  static const int stateLevel = 1;

  /// A district inside one state - the level the heatmap drills down to
  /// (REQ102_12) before handing over to the detailed map.
  static const int districtLevel = 2;

  /// Short ISO-style code, e.g. `JHR`. Stable key for caches and swipe
  /// sessions (C13 keeps one swipe session per state).
  final String code;

  /// Display name, e.g. `Johor`. This is what REQ102_18 searches against.
  final String name;

  final double centreLatitude;
  final double centreLongitude;

  /// Zoom the map settles on when this state is selected from the heatmap or
  /// picked out of a search result (REQ102_22).
  final double defaultZoom;

  /// Outline of the state, drawn as one closed polygon on the heatmap.
  ///
  /// For a multi-part area - Penang's island and mainland, Sabah's 46 pieces -
  /// this is the largest part only. [rings] carries them all.
  final List<GeoPoint> boundary;

  /// [stateLevel] or [districtLevel].
  final int level;

  /// The state a district belongs to, `null` for a state.
  final String? parentCode;

  /// Every closed part of this area. Empty for the hand-drawn state catalogue,
  /// which is single-part by construction; populated for districts, whose
  /// outlines come from the real boundary data.
  final List<List<GeoPoint>> rings;

  /// Bounding box, when it is known. The heatmap fits its projection to this
  /// when it drills into one state's districts.
  final double? minLatitude;
  final double? minLongitude;
  final double? maxLatitude;
  final double? maxLongitude;

  /// Every part of the area, whether it was built with one ring or many.
  List<List<GeoPoint>> get allRings =>
      rings.isEmpty ? <List<GeoPoint>>[boundary] : rings;

  /// Cities and notable locations inside this state, searchable by keyword
  /// (REQ102_19).
  final List<RegionPlace> places;
}

/// One latitude/longitude pair. Deliberately not `LatLng` - that type belongs
/// to `flutter_map`, and nothing below the View layer may import Flutter.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// A city or notable location inside a [Region] (REQ102_19).
class RegionPlace {
  const RegionPlace({
    required this.name,
    required this.regionName,
    required this.latitude,
    required this.longitude,
  });

  final String name;

  /// The state this place sits in - shown as the subtitle of a search result.
  final String regionName;

  final double latitude;
  final double longitude;
}

/// The coastline of one Malaysian landmass - the peninsula, Borneo, or Labuan.
///
/// REQ102_1: the map covers only Malaysia. The detailed map view draws one
/// polygon over the whole world with these rings cut out of it, so the
/// OpenStreetMap tiles only show through inside the country.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these.
class CountryOutline {
  const CountryOutline({required this.name, required this.ring});

  /// "Peninsular Malaysia", "Borneo", "Labuan".
  final String name;

  /// Closed outline of the landmass.
  final List<GeoPoint> ring;
}
