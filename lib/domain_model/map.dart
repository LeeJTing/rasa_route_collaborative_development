/// The explorable map area shown on the dashboard.
///
/// NOTE: the architecture diagram names this entity `Map`. `Map` is a
/// `dart:core` type, so the class is [ExplorationMap]; the file keeps the
/// diagram's name.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class ExplorationMap {
  const ExplorationMap({
    required this.centreLatitude,
    required this.centreLongitude,
    required this.zoom,
    required this.radiusMetres,
    required this.regionName,
    required this.pins,
  });

  final double centreLatitude;
  final double centreLongitude;
  final double zoom;
  final double radiusMetres;
  final String regionName;
  final List<MapPin> pins;
}

enum MapPinKind { restaurant, landmark, food, tourist }

/// A single marker on the map, carrying everything the "Click Map Pin" sheet
/// shows (REQ102_32, UC300 A11).
///
/// The detail travels with the pin rather than being fetched when one is
/// tapped: the sheet then opens instantly, and the fields all come from rows
/// the pin query already had to read. Pin counts are bounded by
/// `MapExplorationLogic.pins(limit:)`, so this stays cheap.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these.
class MapPin {
  const MapPin({
    required this.referenceId,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.weight,
    this.imageUrl,
    this.category,
    this.rating,
    this.servedFoods = const <String>[],
    this.priceRange,
    this.openNow,
    this.distanceMetres,
  });

  final String referenceId;
  final MapPinKind kind;
  final double latitude;
  final double longitude;

  /// The place's name.
  final String label;

  /// Number of matching dishes behind this pin. 1 = a single occurrence.
  final int weight;

  /// Photo of the place, if the source had one.
  final String? imageUrl;

  /// Cuisine or category line - "Authentic Malaysian Cuisine" in the mock-up.
  final String? category;

  final double? rating;

  /// "Serves: Nasi Lemak, Teh Tarik" - the matching local foods on the menu
  /// here, already filtered to whatever the tourist is looking for.
  final List<String> servedFoods;

  /// "RM20-40", or null when no item at this place carries a price.
  final String? priceRange;

  /// Whether the place is open right now. **Null means genuinely unknown** -
  /// no opening hours on record - which the sheet says rather than guessing
  /// "closed".
  final bool? openNow;

  /// Straight-line distance from the tourist's last fix. Null when there is no
  /// fix yet.
  final double? distanceMetres;
}
