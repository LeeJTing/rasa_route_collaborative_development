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

/// A single marker on the map. [weight] is used when the map is drawn as a
/// heat map (1 = a single occurrence).
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class MapPin {
  const MapPin({
    required this.referenceId,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.weight,
  });

  final String referenceId;
  final MapPinKind kind;
  final double latitude;
  final double longitude;
  final String label;
  final int weight;
}
