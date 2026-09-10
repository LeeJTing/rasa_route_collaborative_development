import 'local_food.dart';

/// One entry under the "Location" heading of the search result list
/// (REQ102_18, REQ102_19, REQ102_21).
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.name,
    required this.subtitle,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  /// What the tourist typed against, e.g. `Penang` or `George Town`.
  final String name;

  /// Second line: the state a city belongs to, or `State` for a state itself.
  final String subtitle;

  final PlaceKind kind;

  final double latitude;
  final double longitude;

  /// Where the map should settle when this entry is picked (REQ102_22). A
  /// city zooms past the detailed-view threshold; a state stops short of it.
  final double zoom;
}

/// One place name matched by Postgres, with the score it earned.
///
/// The "addresses" half of Smart Search - a restaurant or a submitted landmark
/// whose *name* answers what was typed. It used to be found by downloading
/// every restaurant and every menu row and scoring the names on the phone;
/// `map_place_search` applies the same ladder in the database and sends back
/// only the handful the list can show.
///
/// Deliberately not a [PlaceSuggestion]: the subtitle wording, the [PlaceKind]
/// and the zoom a result settles at are presentation decisions that belong to
/// `MapExplorationLogic`, not to the layer that reads the row.
class MapPlaceHit {
  const MapPlaceHit({
    required this.referenceId,
    required this.isRestaurant,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.score,
  });

  final String referenceId;

  /// False for a tourist-submitted landmark (C21 keeps the two sources apart).
  final bool isRestaurant;

  final String name;
  final double latitude;
  final double longitude;

  /// 100 exact, 60 the name starts with the keyword, 40 a word in it does,
  /// 20 the name contains it - the ladder the Dart used, unchanged.
  final int score;
}

/// What kind of thing a location result points at (C15).
///
/// The order matters: it is the tie-breaker when two results score the same,
/// so "Penang" lands on the state rather than a street in George Town.
enum PlaceKind { state, city, town, area, landmark, address }

/// The single result list of A8, grouped under "Location" and "Local Food".
///
/// Both lists empty is A8.2 (no result match, M2) - the ViewModel turns that
/// into the message, not this type.
class ExplorationSearchResults {
  const ExplorationSearchResults({
    required this.keyword,
    required this.places,
    required this.foods,
  });

  static const ExplorationSearchResults empty = ExplorationSearchResults(
    keyword: '',
    places: <PlaceSuggestion>[],
    foods: <LocalFood>[],
  );

  final String keyword;

  /// "Location" group - states first, then cities (REQ102_21).
  final List<PlaceSuggestion> places;

  /// "Local Food" group (REQ102_30, REQ102_31).
  final List<LocalFood> foods;
}
