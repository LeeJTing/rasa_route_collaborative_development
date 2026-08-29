/// One searchable place: a city, a town, an area, or a notable location
/// (REQ102_19, REQ102_20).
///
/// States are deliberately **not** in this list. They come from the app's own
/// region catalogue, which also carries their outlines, so keeping them out
/// avoids two sources of truth for the same name.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these.
class MapPlace {
  const MapPlace({
    required this.name,
    required this.kind,
    required this.stateName,
    required this.latitude,
    required this.longitude,
    required this.zoom,
    this.aliases = const <String>[],
  });

  final String name;
  final MapPlaceKind kind;

  /// The state it sits in - the second line of a search result.
  final String stateName;

  final double latitude;
  final double longitude;

  /// Where the map settles when this place is picked (REQ102_22). A landmark
  /// zooms closer than a city.
  final double zoom;

  /// Other names people actually type: "KLCC" for the Petronas Twin Towers,
  /// "PJ" for Petaling Jaya, "Malacca" for Melaka.
  final List<String> aliases;
}

enum MapPlaceKind { city, town, area, landmark }
