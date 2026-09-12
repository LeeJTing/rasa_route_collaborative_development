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

/// A group of nearby places drawn as one marker with a count on it.
///
/// Produced by `map_food_markers` in Postgres, not by the app: at a
/// Malaysia-wide view there are twelve thousand restaurants, and the point of
/// clustering is that the phone never receives them.
///
/// The grid cell is about 56 screen pixels at whatever the current zoom is, so
/// clustering never stops - it just gets finer. A cell holding one place comes
/// back as a real [MapPin] instead, which is why clusters and pins arrive
/// together and both are drawn.
/// What a keyword contributes to the marker query, alongside the filter.
///
/// Three lists because a keyword can reach a place two ways - by naming it, or
/// by naming a dish it serves - and the two id spaces are separate (C21). All
/// empty means no search is active, and the marker query then answers exactly
/// as it did before search existed.
///
/// A plain data type, so the repository, the logic and the ViewModel can all
/// say "the search half of this query" without three more parameters each.
class MapSearchSelection {
  const MapSearchSelection({
    this.foodIds = const <int>[],
    this.restaurantIds = const <int>[],
    this.landmarkIds = const <int>[],
  });

  static const MapSearchSelection none = MapSearchSelection();

  /// Dishes the keyword matched. Every available place serving one of them is
  /// a search result.
  final List<int> foodIds;

  /// Restaurants the keyword named outright.
  final List<int> restaurantIds;

  /// Landmarks the keyword named outright.
  final List<int> landmarkIds;

  bool get isEmpty =>
      foodIds.isEmpty && restaurantIds.isEmpty && landmarkIds.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Stable across two selections that hold the same ids in a different order,
  /// so a cache keyed on this does not miss on tick order.
  String get cacheKey {
    if (isEmpty) return 'none';
    String sorted(List<int> ids) => (List<int>.of(ids)..sort()).join('.');
    return '${sorted(foodIds)}/${sorted(restaurantIds)}/${sorted(landmarkIds)}';
  }
}

class MapCluster {
  const MapCluster({
    required this.latitude,
    required this.longitude,
    required this.count,
    this.searchCount = 0,
  });

  final double latitude;
  final double longitude;

  /// How many places this marker stands for. Always at least 1, and it counts
  /// **every** place in the cell - the filtered map's and the keyword's alike.
  /// There is one grid over both, so there is one number.
  final int count;

  /// How many of [count] are search results. Grouping happens once over both
  /// sets, so a cell is not one thing or the other; it is a proportion.
  final int searchCount;

  /// Any search result in here at all.
  bool get hasSearchResults => searchCount > 0;

  /// Every place in here is a search result.
  bool get isAllSearchResults => searchCount >= count;

  /// Some are, some are not - the case a separate search layer used to draw as
  /// two badges on top of each other.
  bool get isMixed => searchCount > 0 && searchCount < count;

  /// Stable enough to key a widget by, and to compare two loads for equality.
  String get key =>
      '${latitude.toStringAsFixed(4)}:${longitude.toStringAsFixed(4)}';
}

/// The answer to "what happens if I tap this cluster".
///
/// Tapping used to zoom a fixed amount, which for a dense metro was not enough
/// to break the grid cell up - the same count came back and the tap looked like
/// it had done nothing. Postgres now works out where to go:
///
///  * [splitZoom] set - jump straight there, and the cluster visibly breaks up;
///  * [splitZoom] null - the members share coordinates and no zoom will ever
///    separate them, so [members] carries them all to be drawn individually.
class ClusterExpansion {
  const ClusterExpansion({
    required this.splitZoom,
    required this.memberCount,
    this.members = const <MapPin>[],
  });

  static const ClusterExpansion none = ClusterExpansion(
    splitZoom: null,
    memberCount: 0,
  );

  /// The first zoom at which this cluster becomes two or more markers, or null
  /// when it never does within the map's maximum zoom.
  final double? splitZoom;

  /// How many places are inside the cluster.
  final int memberCount;

  /// Every member, individually - populated only when [splitZoom] is null,
  /// because that is the only time the app has to draw them itself.
  final List<MapPin> members;

  bool get splits => splitZoom != null;
}

/// What one viewport query returned. Clusters and pins arrive **together**: the
/// aggregate-or-not decision is made per grid cell, not once for the whole map,
/// so a screen normally holds some of each.
class MapMarkerSet {
  const MapMarkerSet({
    this.clusters = const <MapCluster>[],
    this.pins = const <MapPin>[],
  });

  static const MapMarkerSet empty = MapMarkerSet();

  final List<MapCluster> clusters;
  final List<MapPin> pins;
}

/// One screenful of map pins: what is drawn, and how much of the truth that is.
///
/// The detailed map cannot draw every restaurant in a viewport - at state zoom
/// that is thousands of markers, which is unreadable and slow. Rather than
/// dropping the surplus, Postgres folds each grid cell into one marker: a place
/// when the cell held one, a count when it held several. [limit] is a safety
/// net on the number of *markers*, which the cell grid already bounds to about
/// a screenful.
///
/// [totalInView] is the number of markers the query produced; [placesRepresented]
/// is how many real places stand behind them.
class MapPinPage {
  const MapPinPage({
    required this.pins,
    required this.totalInView,
    required this.limit,
    this.clusters = const <MapCluster>[],
  });

  static const MapPinPage empty = MapPinPage(
    pins: <MapPin>[],
    totalInView: 0,
    limit: 0,
  );

  /// The pins actually drawn - the [limit] closest to the centre of the
  /// viewport.
  final List<MapPin> pins;

  /// Every place inside the viewport that survived the filter, drawn or not.
  final int totalInView;

  /// The cap that was applied, from the zoom level.
  final int limit;

  /// Aggregated markers - the cells that held more than one place. Drawn
  /// alongside [pins], which are the cells that held exactly one.
  final List<MapCluster> clusters;

  /// Whether any marker on screen stands for more than one place.
  bool get isClustered => clusters.isNotEmpty;

  /// Places behind the markers on screen - every pin plus everything inside
  /// every cluster. The honest "how many are here", whatever shape the markers
  /// took.
  int get placesRepresented =>
      pins.length +
      clusters.fold<int>(0, (int sum, MapCluster c) => sum + c.count);

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
/// tapped: the sheet then opens instantly. Map markers carry only what they
/// draw - id, name, position, rating, photo - and the rest is filled in by
/// `MapExplorationLogic.pinDetail` on tap, so carrying them stays cheap.
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
    this.thumbnailUrl,
    this.category,
    this.rating,
    this.servedFoods = const <String>[],
    this.priceRange,
    this.openNow,
    this.distanceMetres,
    this.isSearchResult = false,
  });

  final String referenceId;
  final MapPinKind kind;
  final double latitude;
  final double longitude;

  /// Whether the current keyword is what put this marker on the map.
  ///
  /// The marker's **type**, carried on the marker itself rather than held in a
  /// set beside it, because one query now answers for the filtered map and the
  /// search together and Postgres is what knows which is which. `false` for
  /// every marker while no search is active.
  final bool isSearchResult;

  /// The place's name.
  final String label;

  /// Number of matching dishes behind this pin. 1 = a single occurrence.
  final int weight;

  /// Photo of the place, if the source had one.
  /// The full-size photo, for the detail sheet.
  final String? imageUrl;

  /// The same photo asked for at card size.
  ///
  /// A marker carries both because the pin sheet opens on what the marker
  /// already has and only then fetches the rest: the card wants the small one
  /// and the detail wants the large one, and deriving the small one is a string
  /// rewrite, so neither costs an extra request.
  ///
  /// Null when no smaller variant can be asked for - the caller falls back to
  /// [imageUrl].
  final String? thumbnailUrl;

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
