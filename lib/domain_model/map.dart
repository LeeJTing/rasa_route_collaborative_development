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

/// One screenful of map pins: what is drawn, and how much of the truth that is.
///
/// The detailed map cannot draw every restaurant in a viewport - at state zoom
/// that is thousands of markers, which is unreadable and slow - so [pins] is
/// capped at [limit], and [limit] is chosen from the camera's zoom by
/// `MapExplorationLogic.pinLimitForZoom`.
///
/// [totalInView] is the honest number of places that matched inside the
/// viewport. It exists so the map can *say* how much it is holding back:
/// silently dropping ninety percent of the answer is the same class of defect
/// as a truncated query, and just as hard to notice.
class MapPinPage {
  const MapPinPage({
    required this.pins,
    required this.totalInView,
    required this.limit,
    this.suppressedByZoom = false,
  });

  static const MapPinPage empty = MapPinPage(
    pins: <MapPin>[],
    totalInView: 0,
    limit: 0,
  );

  /// The map is zoomed too far out to draw pins at all - not the same thing as
  /// there being nothing here. Nothing was fetched and nothing was counted, so
  /// [totalInView] is 0 because the question was never asked.
  static const MapPinPage hiddenByZoom = MapPinPage(
    pins: <MapPin>[],
    totalInView: 0,
    limit: 0,
    suppressedByZoom: true,
  );

  /// The pins actually drawn - the [limit] closest to the centre of the
  /// viewport.
  final List<MapPin> pins;

  /// Every place inside the viewport that survived the filter, drawn or not.
  final int totalInView;

  /// The cap that was applied, from the zoom level.
  final int limit;

  /// True when the empty result means "too far out to show pins" rather than
  /// "nothing matched here". Keeps the two apart for anything that reports to
  /// the tourist.
  final bool suppressedByZoom;

  /// Places in view that did not fit on the map.
  int get hiddenCount {
    final int hidden = totalInView - pins.length;
    return hidden > 0 ? hidden : 0;
  }

  bool get hasMore => hiddenCount > 0;
}

enum MapPinKind { restaurant, landmark, food, tourist }

/// A single marker on the map, carrying everything the "Click Map Pin" sheet
/// shows (REQ102_32, UC300 A11).
///
/// The detail travels with the pin rather than being fetched when one is
/// tapped: the sheet then opens instantly, and the fields all come from rows
/// the pin query already had to read. How many pins exist at once is bounded by
/// the zoom, through `MapExplorationLogic.pinLimitForZoom` - see [MapPinPage] -
/// so carrying the detail stays cheap.
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
