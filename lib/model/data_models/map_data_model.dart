import '../../core/json_model.dart';
import 'location_data_model.dart';

/// The map viewport the tourist is currently exploring.
///
/// Not a database table - persisted to local storage so the dashboard reopens
/// where the user left off.
class MapDataModel implements JsonModel {
  const MapDataModel({
    required this.centre,
    this.zoom = 14,
    this.radiusMetres = 2000,
    this.markers = const <MapMarkerDataModel>[],
  });

  final LocationDataModel centre;

  /// Slippy-map zoom level (OpenStreetMap convention, 0-19).
  final double zoom;

  /// Search radius used for "nearby" queries at this viewport.
  final double radiusMetres;

  final List<MapMarkerDataModel> markers;

  factory MapDataModel.fromJson(Map<String, dynamic> json) {
    return MapDataModel(
      centre: LocationDataModel.fromJson(JsonReader.asMap(json['centre'])),
      zoom: JsonReader.asDouble(json['zoom'], fallback: 14),
      radiusMetres: JsonReader.asDouble(json['radius_metres'], fallback: 2000),
      markers: JsonReader.asModelList<MapMarkerDataModel>(
        json['markers'],
        MapMarkerDataModel.fromJson,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'centre': centre.toJson(),
    'zoom': zoom,
    'radius_metres': radiusMetres,
    'markers': markers
        .map((MapMarkerDataModel m) => m.toJson())
        .toList(growable: false),
  };
}

/// A single pin on the map.
class MapMarkerDataModel implements JsonModel {
  const MapMarkerDataModel({
    required this.id,
    required this.kind,
    required this.latitude,
    required this.longitude,
    this.label,
  });

  /// Id of the underlying restaurant / landmark / food, as text.
  final String id;

  /// `restaurant` | `landmark` | `food`.
  final String kind;

  final double latitude;
  final double longitude;
  final String? label;

  factory MapMarkerDataModel.fromJson(Map<String, dynamic> json) {
    return MapMarkerDataModel(
      id: JsonReader.asString(json['id']),
      kind: JsonReader.asString(json['kind']),
      latitude: JsonReader.asDouble(json['latitude']),
      longitude: JsonReader.asDouble(json['longitude']),
      label: JsonReader.asStringOrNull(json['label']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind,
    'latitude': latitude,
    'longitude': longitude,
    'label': label,
  };
}
